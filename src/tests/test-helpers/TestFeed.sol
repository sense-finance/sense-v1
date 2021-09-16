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

    uint256 internal constant EMERGENCY = 911;

    function _scale() internal override virtual returns (uint256 _value) {
        _value = 1e17 * block.number;
        if (block.number >= EMERGENCY) { // we force an invalid scale value
            _value = 0;
        }
    }
}
