// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

interface IPeriphery {
    function onFlashLoan(
        bytes calldata data,
        address initiator,
        address adapter,
        uint48 maturity,
        uint256 cBalIn,
        uint256 amount
    ) external returns (bytes32, uint256);
}

/// @title Assign time-based value to Target tokens
/// @dev In most cases, the only method that will be unique to each adapter type is `_scale`
abstract contract BaseAdapter {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    /* ========== CONSTANTS ========== */

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Target token to divide
    address public immutable target;

    /// @notice Oracle address
    address public immutable oracle;

    /// @notice Token to stake at issuance
    address public immutable stake;

    /// @notice Amount to stake at issuance
    uint256 public immutable stakeSize;

    /// @notice Min maturity (seconds after block.timstamp)
    uint48 public immutable minm;

    /// @notice Max maturity (seconds after block.timstamp)
    uint48 public immutable maxm;

    /// @notice 0 for monthly, 1 for weekly
    uint16 public immutable mode;

    /// @notice Issuance fee
    uint64 public immutable ifee;

    /// @notice 18 decimal number representing the percentage of the total
    /// principal that's set aside for Claims (e.g. 0.1e18 means that 10% of the principal is reserved).
    /// @notice If `0`, it means no principal is set aside for Claims
    uint64 public immutable tilt;

    /// @notice The number this function returns will be used to determine its access by checking for binary
    /// digits using the following scheme: <onRedeemZero(y/n)><collect(y/n)><combine(y/n)><issue(y/n)>
    /// (e.g. 0101 enables `collect` and `issue`, but not `combine`)
    uint16 public immutable level;

    /* ========== DATA STRUCTURES ========== */

    struct LScale {
        // Timestamp of the last scale value
        uint256 timestamp;
        // Last scale value
        uint256 value;
    }

    /* ========== METADATA STORAGE ========== */

    string public name;

    string public symbol;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    /// @notice Cached scale value from the last call to `scale()`
    LScale public lscale;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint48 _minm,
        uint48 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level
    ) {
        // Sanity check
        require(_minm < _maxm, Errors.InvalidMaturityOffsets);
        divider = _divider;
        target = _target;
        oracle = _oracle;
        ifee = _ifee;
        stake = _stake;
        stakeSize = _stakeSize;
        minm = _minm;
        maxm = _maxm;
        mode = _mode;
        tilt = _tilt;
        name = string(abi.encodePacked(ERC20(_target).name(), " Adapter"));
        symbol = string(abi.encodePacked(ERC20(_target).symbol(), "-adapter"));
        level = _level;

        ERC20(_target).safeApprove(_divider, type(uint256).max);
    }

    /// @notice Loan `amount` target to `receiver`, and takes it back after the callback.
    /// @param receiver The contract receiving target, needs to implement the
    /// `onFlashLoan(address user, address adapter, uint48 maturity, uint256 amount)` interface.
    /// @param adapter adapter address
    /// @param maturity maturity
    /// @param cBalIn Claim amount the user has sent in
    /// @param amount The amount of target lent.
    function flashLoan(
        bytes calldata data,
        address receiver,
        address adapter,
        uint48 maturity,
        uint256 cBalIn,
        uint256 amount
    ) external onlyPeriphery returns (bool, uint256) {
        require(ERC20(target).transfer(address(receiver), amount), Errors.FlashTransferFailed);
        (bytes32 keccak, uint256 value) = IPeriphery(receiver).onFlashLoan(
            data,
            msg.sender,
            adapter,
            maturity,
            cBalIn,
            amount
        );
        require(keccak == CALLBACK_SUCCESS, Errors.FlashCallbackFailed);
        require(ERC20(target).transferFrom(address(receiver), address(this), amount), Errors.FlashRepayFailed);
        return (true, value);
    }

    /// @notice Calculate and return this adapter's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate, or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @return value WAD Scale value
    function scale() external virtual returns (uint256) {
        uint256 value = _scale();
        uint256 lvalue = lscale.value;
        uint256 elapsed = block.timestamp - lscale.timestamp;

        if (value != lvalue) {
            // update value only if different than the previous
            lscale.value = value;
            lscale.timestamp = block.timestamp;
        }

        return value;
    }

    /* ========== REQUIRED VALUE GETTERS ========== */

    /// @notice Scale getter to be overriden by child contracts
    /// @dev This function _must_ return an 18 decimal number representing the current exchange rate
    /// between the Target and the Underlying.
    function _scale() internal virtual returns (uint256);

    /// @notice Underlying token address getter that must be overriden by child contracts
    function underlying() external view virtual returns (address);

    /// @notice Returns the current price of the underlying in ETH terms
    function getUnderlyingPrice() external view virtual returns (uint256);

    /* ========== REQUIRED UTILITIES ========== */

    /// @notice Deposits underlying `amount`in return for target. Must be overriden by child contracts
    /// @param amount Underlying amount
    /// @return amount of target returned
    function wrapUnderlying(uint256 amount) external virtual returns (uint256);

    /// @notice Deposits target `amount`in return for underlying. Must be overriden by child contracts
    /// @param amount Target amount
    /// @return amount of underlying returned
    function unwrapTarget(uint256 amount) external virtual returns (uint256);

    /* ========== OPTIONAL HOOKS ========== */

    /// @notice Notification whenever the Divider adds or removes Target
    function notify(
        address, /* usr */
        uint256, /* amt */
        bool /* join */
    ) public virtual {
        return;
    }

    /// @notice Hook called whenever a user redeems Zeros
    function onZeroRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual {
        return;
    }

    /* ========== PUBLIC STORAGE ACCESSORS ========== */

    function getMaturityBounds() external view returns (uint128, uint128) {
        return (minm, maxm);
    }

    function getStakeAndTarget()
        external
        view
        returns (
            address,
            address,
            uint256
        )
    {
        return (target, stake, stakeSize);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPeriphery() {
        require(Divider(divider).periphery() == msg.sender, Errors.OnlyPeriphery);
        _;
    }
}
