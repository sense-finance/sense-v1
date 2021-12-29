// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

abstract contract IController {
    function supportTarget(address _target, bool _support) external virtual;
}
