// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

contract ForkTest is Test {
    uint256 public mainnetFork;

    function fork() public {
        mainnetFork = vm.createFork(getChain("mainnet").rpcUrl);
        vm.selectFork(mainnetFork);
    }

    function fork(uint256 blockNumber) public {
        mainnetFork = vm.createFork(getChain("mainnet").rpcUrl, blockNumber);
        vm.selectFork(mainnetFork);
    }
}
