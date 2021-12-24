// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
abstract contract BaseAdapter is Initializable {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// Configuration --------
    address public divider;
    AdapterParams public adapterParams;
    struct AdapterParams {
        address target; // Target token to divide
        address oracle; // oracle address
        uint256 delta; // max growth per second allowed
        uint256 ifee; // issuance fee
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
        uint8 mode; // 0 for monthly, 1 for weekly
    }

    /// Program state --------
    string public name;
    string public symbol;
    LScale public lscale;
    struct LScale {
        uint256 timestamp; // timestamp of the last scale value
        uint256 value; // last scale value
    }

    event Initialized();

    function initialize(address _divider, AdapterParams memory _adapterParams) public virtual initializer {
        // sanity check
        require(_adapterParams.minm < _adapterParams.maxm, Errors.InvalidMaturityOffsets);

        divider = _divider;
        adapterParams = _adapterParams;
        name = string(abi.encodePacked(ERC20(_adapterParams.target).name(), " Adapter"));
        symbol = string(abi.encodePacked(ERC20(_adapterParams.target).symbol(), "-adapter"));

        ERC20(_adapterParams.target).safeApprove(divider, type(uint256).max);

        emit Initialized();
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
        ERC20 target = ERC20(adapterParams.target);
        require(target.transfer(address(receiver), amount), Errors.FlashTransferFailed);
        (bytes32 keccak, uint256 value) = IPeriphery(receiver).onFlashLoan(
            data,
            msg.sender,
            adapter,
            maturity,
            cBalIn,
            amount
        );
        require(keccak == CALLBACK_SUCCESS, Errors.FlashCallbackFailed);
        require(target.transferFrom(address(receiver), address(this), amount), Errors.FlashRepayFailed);
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

        if (elapsed > 0 && lvalue != 0) {
            // check actual growth vs delta (max growth per sec)
            uint256 growthPerSec = (value > lvalue ? value - lvalue : lvalue - value).fdiv(
                lvalue * elapsed,
                10**ERC20(adapterParams.target).decimals()
            );

            if (growthPerSec > adapterParams.delta) revert(Errors.InvalidScaleValue);
        }

        if (value != lvalue) {
            // update value only if different than the previous
            lscale.value = value;
            lscale.timestamp = block.timestamp;
        }

        return value;
    }

    /// @notice Scale getter to be overriden by child contracts
    /// @dev This function _must_ return an 18 decimal number representing the current exchange rate
    /// between the Target and the Underlying.
    function _scale() internal virtual returns (uint256);

    /// @notice Underlying token address getter that must be overriden by child contracts
    function underlying() external view virtual returns (address);

    /// @notice Tilt value getter that may be overriden by child contracts
    /// @dev Returns `0` by default, which means no principal is set aside for Claims
    /// @dev This function _must_ return an 18 decimal number representing the percentage of the total
    /// principal that's set aside for Claims (e.g. 0.1e18 means that 10% of the principal is reserved).
    function tilt() external virtual returns (uint128) {
        return 0;
    }

    /// @notice Notification whenever the Divider adds or removes Target
    function notify(
        address, /* usr */
        uint256, /* amt */
        bool /* join */
    ) public virtual {
        return;
    }

    /// @notice Deposits underlying `amount`in return for target. Must be overriden by child contracts
    /// @param amount Underlying amount
    /// @return amount of target returned
    function wrapUnderlying(uint256 amount) external virtual returns (uint256);

    /// @notice Deposits target `amount`in return for underlying. Must be overriden by child contracts
    /// @param amount Target amount
    /// @return amount of underlying returned
    function unwrapTarget(uint256 amount) external virtual returns (uint256);

    /// @notice Returns the current price of the underlying in ETH terms
    function getUnderlyingPrice() external view virtual returns (uint256);

    /* ========== ACCESSORS ========== */

    function getTarget() external view returns (address) {
        return adapterParams.target;
    }

    function getIssuanceFee() external view returns (uint256) {
        return adapterParams.ifee;
    }

    function getMaturityBounds() external view returns (uint256, uint256) {
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
        return (adapterParams.target, adapterParams.stake, adapterParams.stakeSize);
    }

    function getMode() external view returns (uint8) {
        return adapterParams.mode;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPeriphery() {
        require(Divider(divider).periphery() == msg.sender, Errors.OnlyPeriphery);
        _;
    }
}
