// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../feed/BaseFeed.sol";

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

    uint256 internal value = 1e18; // one WAD
    uint256 internal constant SECONDS_IN_YEAR = 31536000;

    function _scale() internal override virtual returns (uint256) {
        return value;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }
}
