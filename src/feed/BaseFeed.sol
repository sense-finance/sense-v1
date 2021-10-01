// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../external/WadMath.sol";

// internal references
import "../Divider.sol";

//import "../libs/Errors.sol";

// @title Assign time-based value to target assets
// @dev In most cases, the only function that will be unique to each feed type is `scale`
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

    // @notice Calculate and return this feed's Scale value for the current timestamp
    // @dev For some Targets, such as cTokens, this is simply the exchange rate,
    // or `supply cToken / supply underlying`
    // @dev For other Targets, such as AMM LP shares, specialized logic will be required
    // @dev Reverts if scale value is higher than previous scale + %delta.
    // @dev Reverts if scale value is below the previous scale.
    // @return _value 18 decimal Scale value
    function scale() external virtual returns (uint256 _value) {
        _value = _scale();
        uint256 lvalue = lscale.value;
        //        require(_value < lvalue, Errors.InvalidScaleValue);
        require(_value >= lvalue, "Scale value is invalid");

        if (lvalue != 0) {
            uint256 timeDiff = block.timestamp - lscale.timestamp;
            uint256 growthPerSec = (_value - lvalue).wdiv(lvalue * timeDiff);
            if (growthPerSec > delta) revert("Scale value is invalid");
            //            if (growthPerSec > delta) revert(Errors.InvalidScaleValue);
        }
        lscale.value = _value;
        lscale.timestamp = block.timestamp;
    }

    function _scale() internal virtual returns (uint256 _value);

    event Initialized();
}
