// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { IERC3156FlashLender } from "../external/flashloan/IERC3156FlashLender.sol";
import { IERC3156FlashBorrower } from "../external/flashloan/IERC3156FlashBorrower.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

/// @title Assign value to Target tokens
abstract contract BaseAdapter is IERC3156FlashLender {
    using SafeTransferLib for ERC20;

    /* ========== CONSTANTS ========== */

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Target token to divide
    address public immutable target;

    /// @notice Underlying for the Target
    address public immutable underlying;

    /// @notice Issuance fee
    uint128 public immutable ifee;

    /// @notice adapter params
    AdapterParams public adapterParams;

    /* ========== DATA STRUCTURES ========== */

    struct AdapterParams {
        /// @notice Oracle address
        address oracle;
        /// @notice Token to stake at issuance
        address stake;
        /// @notice Amount to stake at issuance
        uint256 stakeSize;
        /// @notice Min maturity (seconds after block.timstamp)
        uint256 minm;
        /// @notice Max maturity (seconds after block.timstamp)
        uint256 maxm;
        /// @notice WAD number representing the percentage of the total
        /// principal that's set aside for Yield Tokens (e.g. 0.1e18 means that 10% of the principal is reserved).
        /// @notice If `0`, it means no principal is set aside for Yield Tokens
        uint64 tilt;
        /// @notice The number this function returns will be used to determine its access by checking for binary
        /// digits using the following scheme: <onRedeem(y/n)><collect(y/n)><combine(y/n)><issue(y/n)>
        /// (e.g. 0101 enables `collect` and `issue`, but not `combine`)
        uint48 level;
        /// @notice 0 for monthly, 1 for weekly
        uint16 mode;
    }

    /* ========== METADATA STORAGE ========== */

    string public name;

    string public symbol;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) {
        divider = _divider;
        target = _target;
        underlying = _underlying;
        ifee = _ifee;
        adapterParams = _adapterParams;

        name = string(abi.encodePacked(ERC20(_target).name(), " Adapter"));
        symbol = string(abi.encodePacked(ERC20(_target).symbol(), "-adapter"));

        ERC20(_target).approve(divider, type(uint256).max);
        ERC20(_adapterParams.stake).approve(divider, type(uint256).max);
    }

    /// @notice Loan `amount` target to `receiver`, and takes it back after the callback.
    /// @param receiver The contract receiving target, needs to implement the
    /// `onFlashLoan(address user, address adapter, uint256 maturity, uint256 amount)` interface.
    /// @param amount The amount of target lent.
    /// @param data (encoded adapter address, maturity and YT amount the use has sent in)
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address, /* fee */
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();
        ERC20(target).safeTransfer(address(receiver), amount);
        bytes32 keccak = IERC3156FlashBorrower(receiver).onFlashLoan(msg.sender, target, amount, 0, data);
        if (keccak != CALLBACK_SUCCESS) revert Errors.FlashCallbackFailed();
        ERC20(target).safeTransferFrom(address(receiver), address(this), amount);
        return true;
    }

    /* ========== REQUIRED VALUE GETTERS ========== */

    /// @notice Calculate and return this adapter's Scale value for the current timestamp. To be overriden by child contracts
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate, or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @dev This function _must_ return a WAD number representing the current exchange rate
    /// between the Target and the Underlying.
    /// @return value WAD Scale value
    function scale() external virtual returns (uint256);

    /// @notice Cached scale value getter
    /// @dev For situations where you need scale from a view function
    function scaleStored() external view virtual returns (uint256);

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

    function flashFee(address token, uint256) external view returns (uint256) {
        if (token != target) revert Errors.TokenNotSupported();
        return 0;
    }

    function maxFlashLoan(address token) external view override returns (uint256) {
        return ERC20(token).balanceOf(address(this));
    }

    /* ========== OPTIONAL HOOKS ========== */

    /// @notice Notification whenever the Divider adds or removes Target
    function notify(
        address, /* usr */
        uint256, /* amt */
        bool /* join */
    ) public virtual {
        return;
    }

    /// @notice Hook called whenever a user redeems PT
    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual {
        return;
    }

    /* ========== PUBLIC STORAGE ACCESSORS ========== */

    function getMaturityBounds() external view virtual returns (uint256, uint256) {
        return (adapterParams.minm, adapterParams.maxm);
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
        return (target, adapterParams.stake, adapterParams.stakeSize);
    }

    function mode() external view returns (uint256) {
        return adapterParams.mode;
    }

    function tilt() external view returns (uint256) {
        return adapterParams.tilt;
    }

    function level() external view returns (uint256) {
        return adapterParams.level;
    }
}
