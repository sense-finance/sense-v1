// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

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

    function load(address, bytes32) external virtual returns (bytes32);

    // Expects an error on next call
    function expectRevert(bytes calldata) external virtual;

    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
    function prank(address,address) virtual external;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
    function startPrank(address,address) virtual external;

    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() virtual external;
}
