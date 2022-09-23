// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

abstract contract Hevm {
    // This allows us to getRecordedLogs()
    struct Log {
        bytes32[] topics;
        bytes data;
    }

    // Set block.timestamp
    function warp(uint256) external virtual;

    // Set block.number
    function roll(uint256) external virtual;

    // Set block.basefee
    function fee(uint256) external virtual;

    // Set block.chainid
    function chainId(uint256) external virtual;

    // Loads a storage slot from an address
    function load(address account, bytes32 slot) external virtual returns (bytes32);

    // Stores a value to an address' storage slot
    function store(
        address account,
        bytes32 slot,
        bytes32 value
    ) external virtual;

    // Signs data
    function sign(uint256 privateKey, bytes32 digest)
        external
        virtual
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        );

    // Computes address for a given private key
    function addr(uint256 privateKey) external virtual returns (address);

    // Gets the nonce of an account
    function getNonce(address account) external virtual returns (uint64);

    // Sets the nonce of an account
    // The new nonce must be higher than the current nonce of the account
    function setNonce(address account, uint64 nonce) external virtual;

    // Performs a foreign function call via terminal
    function ffi(string[] calldata) external virtual returns (bytes memory);

    // Set environment variables, (name, value)
    function setEnv(string calldata, string calldata) external virtual;

    // Read environment variables, (name) => (value)
    function envBool(string calldata) external virtual returns (bool);

    function envUint(string calldata) external virtual returns (uint256);

    function envInt(string calldata) external virtual returns (int256);

    function envAddress(string calldata) external virtual returns (address);

    function envBytes32(string calldata) external virtual returns (bytes32);

    function envString(string calldata) external virtual returns (string memory);

    function envBytes(string calldata) external virtual returns (bytes memory);

    // Read environment variables as arrays, (name, delim) => (value[])
    function envBool(string calldata, string calldata) external virtual returns (bool[] memory);

    function envUint(string calldata, string calldata) external virtual returns (uint256[] memory);

    function envInt(string calldata, string calldata) external virtual returns (int256[] memory);

    function envAddress(string calldata, string calldata) external virtual returns (address[] memory);

    function envBytes32(string calldata, string calldata) external virtual returns (bytes32[] memory);

    function envString(string calldata, string calldata) external virtual returns (string[] memory);

    function envBytes(string calldata, string calldata) external virtual returns (bytes[] memory);

    // Sets the *next* call's msg.sender to be the input address
    function prank(address) external virtual;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called
    function startPrank(address) external virtual;

    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
    function prank(address, address) external virtual;

    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
    function startPrank(address, address) external virtual;

    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() external virtual;

    // Sets an address' balance
    function deal(address who, uint256 newBalance) external virtual;

    // Sets an address' code
    function etch(address who, bytes calldata code) external virtual;

    // Expects an error on next call
    function expectRevert() external virtual;

    function expectRevert(bytes calldata) external virtual;

    function expectRevert(bytes4) external virtual;

    // Record all storage reads and writes
    function record() external virtual;

    // Gets all accessed reads and write slot from a recording session, for a given address
    function accesses(address) external virtual returns (bytes32[] memory reads, bytes32[] memory writes);

    // Record all the transaction logs
    function recordLogs() external virtual;

    // Gets all the recorded logs
    function getRecordedLogs() external virtual returns (Log[] memory);

    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
    // Second form also checks supplied address against emitting contract.
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external virtual;

    function expectEmit(
        bool,
        bool,
        bool,
        bool,
        address
    ) external virtual;

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

    // Gets the bytecode for a contract in the project given the path to the contract.
    function getCode(string calldata) external virtual returns (bytes memory);

    // Label an address in test traces
    function label(address addr, string calldata label) external virtual;

    // When fuzzing, generate new inputs if conditional not met
    function assume(bool) external virtual;

    // Set block.coinbase (who)
    function coinbase(address) external virtual;

    // Using the address that calls the test contract or the address provided
    // as the sender, has the next call (at this call depth only) create a
    // transaction that can later be signed and sent onchain
    function broadcast() external virtual;

    function broadcast(address) external virtual;

    // Using the address that calls the test contract or the address provided
    // as the sender, has all subsequent calls (at this call depth only) create
    // transactions that can later be signed and sent onchain
    function startBroadcast() external virtual;

    function startBroadcast(address) external virtual;

    // Stops collecting onchain transactions
    function stopBroadcast() external virtual;

    // Snapshot the current state of the evm.
    // Returns the id of the snapshot that was created.
    // To revert a snapshot use `revertTo`
    function snapshot() external virtual returns (uint256);

    // Revert the state of the evm to a previous snapshot
    // Takes the snapshot id to revert to.
    // This deletes the snapshot and all snapshots taken after the given snapshot id.
    function revertTo(uint256) external virtual returns (bool);

    // Creates a new fork with the given endpoint and block and returns the identifier of the fork
    function createFork(string calldata, uint256) external virtual returns (uint256);

    // Creates a new fork with the given endpoint and the _latest_ block and returns the identifier of the fork
    function createFork(string calldata) external virtual returns (uint256);

    // Creates _and_ also selects a new fork with the given endpoint and block and returns the identifier of the fork
    function createSelectFork(string calldata, uint256) external virtual returns (uint256);

    // Creates _and_ also selects a new fork with the given endpoint and the latest block and returns the identifier of the fork
    function createSelectFork(string calldata) external virtual returns (uint256);

    // Takes a fork identifier created by `createFork` and sets the corresponding forked state as active.
    function selectFork(uint256) external virtual;

    /// Returns the currently active fork
    /// Reverts if no fork is currently active
    function activeFork() external virtual returns (uint256);

    // Updates the currently active fork to given block number
    // This is similar to `roll` but for the currently active fork
    function rollFork(uint256) external virtual;

    // Updates the given fork to given block number
    function rollFork(uint256 forkId, uint256 blockNumber) external virtual;

    /// Returns the RPC url for the given alias
    function rpcUrl(string calldata) external virtual returns (string memory);

    /// Returns all rpc urls and their aliases `[alias, url][]`
    function rpcUrls() external virtual returns (string[2][] memory);
}
