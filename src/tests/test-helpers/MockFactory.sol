// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { BaseFactory } from "../../feeds/BaseFactory.sol";

contract MockFactory is BaseFactory {
    mapping(address => bool) public targets;

    constructor(
        address _implementation,
        address _divider,
        uint256 _delta,
        address _airdropToken
    ) BaseFactory(address(0), _implementation, _divider, _delta, _airdropToken) {}

    function _exists(address _target) internal override virtual returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

}
