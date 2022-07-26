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

    // Sets an address' code, (who, newCode)
    function etch(address, bytes calldata) external virtual;

    // Expects an error on next call
    function expectRevert(bytes calldata) external virtual;

    function expectRevert(bytes4) external virtual;

    function expectRevert() external virtual;

    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external virtual;

    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
    function prank(address) external virtual;

    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
    function prank(address, address) external virtual;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
    function startPrank(address) external virtual;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
    function startPrank(address, address) external virtual;

    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() external virtual;

    // Record all storage reads and writes
    function record() external virtual;

    // Gets all accessed reads and write slot from a recording session, for a given address
    function accesses(address) external virtual returns (bytes32[] memory reads, bytes32[] memory writes);

    // Mocks a call to an address, returning specified data.
    // Calldata can either be strict or a partial match, e.g. if you only
    // pass a Solidity selector to the expected calldata, then the entire Solidity
    // function will be mocked.
    function mockCall(
        address,
        bytes calldata,
        bytes calldata
    ) external virtual;

    // Clears all mocked calls
    function clearMockedCalls() external virtual;

    // Expect a call to an address with the specified calldata.
    // Calldata can either be strict or a partial match
    function expectCall(address, bytes calldata) external virtual;

    // Gets the code from an artifact file. Takes in the relative path to the json file
    function getCode(string calldata) external virtual returns (bytes memory);

    // Labels an address in call traces
    function label(address, string calldata) external virtual;

    // If the condition is false, discard this run's fuzz inputs and generate new ones
    function assume(bool) external virtual;

    // Creates a new fork with the given endpoint and block and returns the identifier of the fork
    function createFork(string calldata urlOrAlias, uint256 block) external virtual returns (uint256);

    // Creates a new fork with the given endpoint and the _latest_ block and returns the identifier of the fork
    function createFork(string calldata urlOrAlias) external virtual returns (uint256);

    // Creates _and_ also selects a new fork with the given endpoint and block and returns the identifier of the fork
    function createSelectFork(string calldata urlOrAlias, uint256 block) external virtual returns (uint256);

    // Creates _and_ also selects a new fork with the given endpoint and the latest block and returns the identifier of the fork
    function createSelectFork(string calldata urlOrAlias) external virtual returns (uint256);

    // Takes a fork identifier created by `createFork` and sets the corresponding forked state as active.
    function selectFork(uint256 forkId) external virtual;

    /// Returns the currently active fork
    /// Reverts if no fork is currently active
    function activeFork() external virtual returns (uint256);

    // Updates the currently active fork to given block number
    // This is similar to `roll` but for the currently active fork
    function rollFork(uint256) external virtual;

    // Updates the given fork to given block number
    function rollFork(uint256 forkId, uint256 blockNumber) external virtual;

    // Read environment variables, (name) => (value)
    function envBool(string calldata) external virtual returns (bool);

    function envUint(string calldata) external virtual returns (uint256);

    function envInt(string calldata) external virtual returns (int256);

    function envAddress(string calldata) external virtual returns (address);

    function envBytes32(string calldata) external virtual returns (bytes32);

    function envString(string calldata) external virtual returns (string memory);

    function envBytes(string calldata) external virtual returns (bytes memory);
}
