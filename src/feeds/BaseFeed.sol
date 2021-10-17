// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/errors.sol";

/// @title Assign time-based value to target assets
/// @dev In most cases, the only function that will be unique to each feed type is `scale`
abstract contract BaseFeed is Initializable {
    using FixedMath for uint256;

    address public target;
    address public divider;
    address public twrapper;
    uint256 public delta;
    string public name;
    string public symbol;
    LScale public lscale;

    struct LScale {
        uint256 timestamp; // timestamp of the last scale value
        uint256 value; // last scale value
    }

    function initialize(
        address _target,
        address _divider,
        uint256 _delta,
        address _twrapper
    ) external virtual initializer {
        divider = _divider;
        delta = _delta;
        target = _target;
        twrapper = _twrapper;
        name = string(abi.encodePacked(ERC20(target).name(), " Yield"));
        symbol = string(abi.encodePacked(ERC20(target).symbol(), "-yield"));
        emit Initialized();
    }

    /// @notice Calculate and return this feed's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate,
    /// or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @return _value WAD Scale value
    function scale() external virtual returns (uint256 _value) {
        _value = _scale();
        uint256 lvalue = lscale.value;
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        if (timeDiff > 0 && lvalue != 0) {
            uint256 growthPerSec = (_value > lvalue ? _value - lvalue : lvalue - _value).fdiv(
                lvalue * timeDiff,
                10**ERC20(target).decimals()
            );
            if (growthPerSec > delta) revert(Errors.InvalidScaleValue);
        }

        if (_value != lscale.value) {
            // update value only if different than previous
            lscale.value = _value;
            lscale.timestamp = block.timestamp;
        }
    }

    /// @notice Tilt value read that may be overriden by child contracts
    /// @dev By default, it's implemented as `0`, which means no principal is set aside for Claims
    function tilt() external virtual returns (uint256) {
        return 0;
    }

    /// @notice Actual scale value check that must be overriden by child contracts
    function _scale() internal virtual returns (uint256 _value);

    event Initialized();
    event WTargetAdded(address indexed twrapper);
}
