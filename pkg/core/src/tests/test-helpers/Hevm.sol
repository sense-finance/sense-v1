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

    // Performs a foreign function call via terminal, (stringInputs) => (result)
    function ffi(string[] calldata) external virtual returns (bytes memory);

    // Loads a storage slot from an address (who, slot)
    function load(address, bytes32) external virtual returns (bytes32);

    // Sets an address' code, (who, newCode)
    function etch(address, bytes calldata) external virtual;
}
