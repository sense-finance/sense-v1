// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../external/WadMath.sol";
import "../external/SafeMath.sol";

// internal references
import "../Divider.sol";
//import "./libs/Errors.sol";

// interfaces
import "../interfaces/IFeed.sol";

// @title Assign time-based value to target assets
// @dev In most cases, the only function that will be unique to each feed type is `scale`
abstract contract BaseFeed is IFeed {
    using WadMath for uint256;
    using SafeMath for uint256;
    //    using Errors for string;

    address public override target;
    address public override divider;
    string public override name;
    string public override symbol;
    uint256 public delta;
    LScale public lscale;

    struct LScale {
        uint256 timestamp; // timestamp of the last scale value
        uint256 value; // last scale value
    }

    /**
     * @param _divider address of the divider
     * @param _delta value in percentage used to check for invalid scale values
     */
    constructor(
        address _target,
        address _divider,
        uint256 _delta
    ) {
        // TODO: add input validation?
        target = _target;
        divider = _divider;
        delta = _delta;

        name = string(abi.encodePacked(ERC20(target).name(), " Yield"));
        symbol = string(abi.encodePacked(ERC20(target).symbol(), "-yield"));
    }

    // @notice Calculate and return this feed's Scale value for the current timestamp
    // @dev For some Targets, such as cTokens, this is simply the exchange rate,
    // or `supply cToken / supply underlying`
    // @dev For other Targets, such as AMM LP shares, specialized logic will be required
    // @dev Reverts if scale value is higher than previous scale + %delta.
    // @dev Reverts if scale value is below the previous scale.
    // @return _value 18 decimal Scale value
    function scale() external virtual override returns (uint256 _value) {
        _value = _scale();
        uint256 lvalue = lscale.value;
        //        require(_value < lvalue, Errors.InvalidScaleValue);
        require(_value >= lvalue, "Scale value is invalid");

        if (lvalue != 0) {
            uint256 timeDiff = block.timestamp - lscale.timestamp;
            uint256 growthPerSec = (_value.wdiv(lvalue) - lvalue) / timeDiff;
            if (growthPerSec > delta) revert("Scale value is invalid");
            emit Lina(_value, lvalue, timeDiff, _value.div(lvalue).div(timeDiff));

            // if (valPerSec > lvalPerSec.add(lvalPerSec.wmul(delta).wdiv(100))) revert(Errors.InvalidScaleValue);
        }
        lscale.value = _value;
        lscale.timestamp = block.timestamp;
    }

    function _scale() internal virtual returns (uint256 _value);
    event Lina(uint256 a, uint256 b, uint256 c, uint256 d);
}
