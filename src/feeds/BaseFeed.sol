// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/Errors.sol";

interface IPeriphery {
    function onFlashLoan(
        bytes calldata data,
        address initiator,
        address feed,
        uint256 maturity,
        uint256 amount
    ) external returns (bytes32, uint256);
}

/// @title Assign time-based value to Target tokens
/// @dev In most cases, the only method that will be unique to each feed type is `_scale`
abstract contract BaseFeed is Initializable {
    using FixedMath for uint256;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// Configuration --------
    address public divider;
    FeedParams public feedParams;
    struct FeedParams {
        address target; // Target token to divide
        address oracle; // oracle address
        uint256 delta; // max growth per second allowed
        uint256 ifee; // issuance fee
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
    }

    /// Program state --------
    string public name;
    string public symbol;
    LScale public _lscale;
    struct LScale {
        uint256 timestamp; // timestamp of the last scale value
        uint256 value; // last scale value
    }

    event Initialized();

    /* ========== GETTERS ========== */

    function initialize(address _divider, FeedParams memory _feedParams) public virtual initializer {
        // sanity check
        require(_feedParams.minm < _feedParams.maxm, Errors.InvalidMaturityOffsets);

        divider = _divider;
        feedParams = _feedParams;
        name = string(abi.encodePacked(ERC20(_feedParams.target).name(), " Feed"));
        symbol = string(abi.encodePacked(ERC20(_feedParams.target).symbol(), "-feed"));

        ERC20(_feedParams.target).approve(divider, type(uint256).max);

        emit Initialized();
    }

    /// @notice Loan `amount` target to `receiver`, and takes it back after the callback.
    /// @param receiver The contract receiving target, needs to implement the
    /// `onFlashLoan(address user, address feed, uint256 maturity, uint256 amount)` interface.
    /// @param feed feed address
    /// @param maturity maturity
    /// @param amount The amount of target lent.
    function flashLoan(
        bytes calldata data,
        address receiver,
        address feed,
        uint256 maturity,
        uint256 amount
    ) external onlyPeriphery returns (bool, uint256) {
        ERC20 target = ERC20(feedParams.target);
        require(target.transfer(address(receiver), amount), Errors.FlashTransferFailed);
        (bytes32 keccak, uint256 value) = IPeriphery(receiver).onFlashLoan(data, msg.sender, feed, maturity, amount);
        require(keccak == CALLBACK_SUCCESS, Errors.FlashCallbackFailed);
        require(target.transferFrom(address(receiver), address(this), amount), Errors.FlashRepayFailed);
        return (true, value);
    }

    /// @notice Calculate and return this feed's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate, or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @return _value WAD Scale value
    function scale() external virtual returns (uint256) {
        uint256 _value = _scale();
        uint256 lvalue = _lscale.value;
        uint256 elapsed = block.timestamp - _lscale.timestamp;

        if (elapsed > 0 && lvalue != 0) {
            // check actual growth vs delta (max growth per sec)
            uint256 growthPerSec = (_value > lvalue ? _value - lvalue : lvalue - _value).fdiv(
                lvalue * elapsed,
                10**ERC20(feedParams.target).decimals()
            );

            if (growthPerSec > feedParams.delta) revert(Errors.InvalidScaleValue);
        }

        if (_value != lvalue) {
            // update value only if different than the previous
            _lscale.value = _value;
            _lscale.timestamp = block.timestamp;
        }

        return _value;
    }

    /// @notice Scale getter that must be overriden by child contracts
    function _scale() internal virtual returns (uint256);

    /// @notice Underlying token address getter that must be overriden by child contracts
    function underlying() external virtual returns (address);

    /// @notice Tilt value getter that may be overriden by child contracts
    /// @dev Returns `0` by default, which means no principal is set aside for Claims
    function tilt() external virtual returns (uint256) {
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

    /// @notice Deposits underlying `amount`in return for target. Must be overriden by child contracts.
    /// @param amount Underlying amount
    /// @return amount of target returned
    function wrapUnderlying(uint256 amount) external virtual returns (uint256);

    /// @notice Deposits target `amount`in return for underlying. Must be overriden by child contracts.
    /// @param amount Target amount
    /// @return amount of underlying returned
    function unwrapTarget(uint256 amount) external virtual returns (uint256);

    /* ========== ACCESSORS ========== */

    function getTarget() external view returns (address) {
        return feedParams.target;
    }

    function getIssuanceFee() external view returns (uint256) {
        return feedParams.ifee;
    }

    function getMaturityBounds() external view returns (uint256, uint256) {
        return (feedParams.minm, feedParams.maxm);
    }

    function getStakeSize() external view returns (uint256) {
        return feedParams.stakeSize;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPeriphery() {
        require(Divider(divider).periphery() == msg.sender, Errors.OnlyPeriphery);
        _;
    }
}
