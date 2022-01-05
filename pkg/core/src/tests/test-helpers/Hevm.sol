// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract Hevm {
    // Sets the block timestamp to x
    function warp(uint256 x) public virtual;

    // Sets the block number to x
    function roll(uint256 x) public virtual;

    // Sets the slot loc of contract c to val
    function store(
        address c,
        bytes32 loc,
        bytes32 val
    ) public virtual;

    function ffi(string[] calldata) external virtual returns (bytes memory);
}
