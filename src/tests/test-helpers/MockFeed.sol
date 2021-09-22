// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "../../feed/BaseFeed.sol";

contract MockFeed is BaseFeed {
    uint256 private gps;
    using WadMath for uint256;

    constructor(
        address _target,
        address _divider,
        uint256 _delta,
        uint256 _gps // growth per second
    ) BaseFeed(_target, _divider, _delta) {
        gps = _gps;
    }

    uint256 internal value;
    uint256 public constant INITIAL_VALUE = 1e17;

    function _scale() internal override virtual returns (uint256 _value) {
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        if (value > 0) return value;
        _value = lscale.value > 0 ? (gps.wmul(timeDiff)).wmul(lscale.value) + lscale.value : 1e17;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }
}
