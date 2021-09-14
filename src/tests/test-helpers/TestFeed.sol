pragma solidity ^0.8.6;

// Internal references
import "../../feed/BaseFeed.sol";
import "../../external/tokens/ERC20.sol";

contract TestFeed is BaseFeed {

    constructor(
        address _target,
        address _divider,
        uint256 _delta
    ) BaseFeed(_target, _divider, _delta) {}

    uint256 internal _counter = 1;
    uint256 internal constant EMERGENCY = 911;

    function _scale() internal override virtual returns (uint256 _value) {
        _value = 1e17 * _counter;
        if (_counter >= EMERGENCY) { // we force an invalid scale value
            _value = 0;
        }
        _counter++;
    }

    function setCounter(uint256 num) public {
        _counter = num;
        emit Counter(_counter);
    }
    event Counter(uint256 _counter);
}
