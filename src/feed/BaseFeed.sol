pragma solidity ^0.8.6;

// External references
import "../external/WadMath.sol";
import "../external/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Internal references
import "../interfaces/IFeed.sol";
import "../interfaces/IDivider.sol";

//import "./libs/Errors.sol";

/// @title Assign time-based value to target assets
/// @dev In most cases, the only function that will be unique to each feed type is `scale`
abstract contract BaseFeed is IFeed {
    using WadMath for uint256;
    using SafeMath for uint256;
    //    using Errors for string;

    address public override target;
    address public override divider;
    string public override name;
    string public override symbol;
    uint256 public delta;
    uint256 public lscale;

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

    /// @notice Calculate and return this feed's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate,
    /// or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @dev Reverts if scale value is higher than previous scale + %delta.
    /// @dev Reverts if scale value is below the previous scale.
    /// @return _value 18 decimal Scale value
    function scale() external virtual override returns (uint256 _value) {
        _value = _scale();
        if (_value < lscale || (lscale != 0 && _value > lscale.add(lscale.wmul(delta).wdiv(100)))) {
            IDivider(divider).setFeed(address(this), false);
            //            revert(Errors.InvalidScaleValue);
            revert("Scale value is invalid");
        }
        lscale = _value;
    }

    function _scale() internal virtual returns (uint256 _value);
}
