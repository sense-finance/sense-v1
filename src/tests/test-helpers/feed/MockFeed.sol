// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../../feed/BaseFeed.sol";

contract MockFeed is BaseFeed {

    constructor(
        address _target,
        address _divider,
        uint256 _delta
    ) BaseFeed(_target, _divider, _delta) {}

    uint256 internal value = 0;

    function _scale() internal override virtual returns (uint256 _value) {
        _value = value > 0 ? value : 1e17 * block.number;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }
}
