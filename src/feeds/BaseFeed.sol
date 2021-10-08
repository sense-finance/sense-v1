// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "solmate/erc20/ERC20.sol";
import { WadMath } from "../external/WadMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/errors.sol";

/// @title Assign time-based value to target assets
/// @dev In most cases, the only function that will be unique to each feed type is `scale`
abstract contract BaseFeed is Initializable {
    using WadMath for uint256;

    address public target;
    address public divider; // TODO: must be hardcoded!
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
        uint256 _delta
    ) external virtual initializer {
        // TODO: only factory?
        // TODO: add input validation?
        divider = _divider;
        delta = _delta;
        target = _target;
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
        require(_value >= lvalue, Errors.InvalidScaleValue);
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        if (timeDiff > 0 && lvalue != 0) {
            uint256 growthPerSec = (_value - lvalue).wdiv(lvalue * timeDiff);
            if (growthPerSec > delta) revert(Errors.InvalidScaleValue);
        }
        if (_value != lscale.value) {
            // update value only if different than previous
            lscale.value = _value;
            lscale.timestamp = block.timestamp;
        }
    }

    /// @notice Actual scale value check that must be overriden by child contracts
    function _scale() internal virtual returns (uint256 _value);

    event Initialized();
}
