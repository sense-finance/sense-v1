// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
//import "../libs/Errors.sol";
import "../access/Warded.sol";

// @title Sense Protocol controller
contract Controller is Warded {
    mapping(address => bool) public targets;

    constructor() Warded() {}

    function supportTarget(address _target, bool _support) external onlyWards {
        require(targets[_target] != _support, "Target is not supported");
        //        require(targets[_target] != _support, Errors.ExistingValue);
        targets[_target] = _support;
        emit Supported(_target);
    }

    event Supported(address target);
}
