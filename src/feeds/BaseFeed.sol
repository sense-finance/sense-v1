// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/Errors.sol";

/// @title Assign time-based value to Target tokens
/// @dev In most cases, the only method that will be unique to each feed type is `_scale`
abstract contract BaseFeed is Initializable {
    using FixedMath for uint256;

    /// Configuration --------
    address public divider;
    FeedParams public feedParams;
    struct FeedParams {
        address target; // Target token to divide
        uint256 delta;  // max growth per second allowed
        uint256 ifee;   // issuance fee
        address stake;  // token to stake at issuance
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
        uint256 value;     // last scale value
    }

    event Initialized();

    /* ========== GETTERS ========== */

    function initialize(address _divider, FeedParams memory _feedParams) public virtual initializer {
        // sanity check
        require(_feedParams.minm < _feedParams.maxm, "Invalid maturity offsets");

        divider    = _divider;
        feedParams = _feedParams;
        name   = string(abi.encodePacked(ERC20(_feedParams.target).name(), " Feed"));
        symbol = string(abi.encodePacked(ERC20(_feedParams.target).symbol(), "-feed"));

        ERC20(_feedParams.target).approve(divider, type(uint256).max);

        emit Initialized();
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

    /// @notice Tilt value getter that may be overriden by child contracts
    /// @dev Returns `0` by default, which means no principal is set aside for Claims
    function tilt() external virtual returns (uint256) {
        return 0;
    }

    /// @notice Notification whenever the Divider adds or removes Target
    function notify(address /* usr */, uint256 /* amt */, bool /* join */) public virtual {
        return;
    }

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
}
