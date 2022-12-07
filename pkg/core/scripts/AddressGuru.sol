// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { AddressBook } from "./AddressBook.sol";
import { AddressBookGoerli } from "./AddressBookGoerli.sol";

contract AddressGuru {
    uint256 public chainId;
    constructor(uint256 _chainId) {
        chainId = _chainId;
    }

    function divider() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.DIVIDER_1_2_0 : AddressBookGoerli.DIVIDER;
    }

    function periphery() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.PERIPHERY_1_4_0 : AddressBookGoerli.PERIPHERY;
    }

    function spaceFactory() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.SPACE_FACTORY_1_3_0 : AddressBookGoerli.SPACE_FACTORY;
    }

    function balancerVault() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.BALANCER_VAULT : AddressBookGoerli.BALANCER_VAULT;
    }

    function poolManager() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.POOL_MANAGER_1_3_0 : AddressBookGoerli.POOL_MANAGER;
    }

    function oracle() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.SENSE_MASTER_ORACLE : AddressBookGoerli.SENSE_MASTER_ORACLE;
    }

    // underlyings

    function dai() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.DAI : AddressBookGoerli.DAI;
    }

    function usdc() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.USDC : AddressBookGoerli.USDC;
    }

    function usdt() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.USDT : AddressBookGoerli.USDT;
    }

    function weth() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.WETH : AddressBookGoerli.WETH;
    }

    // targets

    function cDai() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.cDAI : AddressBookGoerli.cDAI;
    }

    function cUsdc() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.cUSDC : AddressBookGoerli.cUSDC;
    }

    function cUsdt() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.cUSDT : AddressBookGoerli.cUSDT;
    }

    function BB_wstETH4626() public returns (address) {
        return chainId == AddressBook.MAINNET ? AddressBook.BB_wstETH4626 : AddressBookGoerli.BB_wstETH4626;
    }
    
}