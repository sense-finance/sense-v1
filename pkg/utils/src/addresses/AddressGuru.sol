// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { AddressBook } from "./AddressBook.sol";
import { AddressBookGoerli } from "./AddressBookGoerli.sol";

library Constants {
    // chains
    uint256 public constant MAINNET = 1;
    uint256 public constant GOERLI = 5;
    uint256 public constant FORK = 111;
}

contract AddressGuru {
    uint256 public chainId;

    constructor() {
        uint256 id;
        assembly {
            id := chainid()
        }
        chainId = id == Constants.FORK ? Constants.MAINNET : id;
    }

    function multisig() public view returns (address) {
        return
            chainId == Constants.FORK || chainId == Constants.MAINNET
                ? AddressBook.SENSE_MULTISIG
                : AddressBookGoerli.SENSE_MULTISIG;
    }

    function divider() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.DIVIDER_1_2_0 : AddressBookGoerli.DIVIDER;
    }

    function periphery() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.PERIPHERY_1_4_0 : AddressBookGoerli.PERIPHERY;
    }

    function spaceFactory() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.SPACE_FACTORY_1_3_0 : AddressBookGoerli.SPACE_FACTORY;
    }

    function balancerVault() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.BALANCER_VAULT : AddressBookGoerli.BALANCER_VAULT;
    }

    function poolManager() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.POOL_MANAGER_1_3_0 : AddressBookGoerli.POOL_MANAGER;
    }

    function oracle() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.SENSE_MASTER_ORACLE : AddressBookGoerli.SENSE_MASTER_ORACLE;
    }

    // underlyings

    function dai() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.DAI : AddressBookGoerli.DAI;
    }

    function usdc() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.USDC : AddressBookGoerli.USDC;
    }

    function usdt() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.USDT : AddressBookGoerli.USDT;
    }

    function weth() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.WETH : AddressBookGoerli.WETH;
    }

    // targets

    function cDai() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.cDAI : AddressBookGoerli.cDAI;
    }

    function cUsdc() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.cUSDC : AddressBookGoerli.cUSDC;
    }

    function cUsdt() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.cUSDT : AddressBookGoerli.cUSDT;
    }

    function BB_wstETH4626() public view returns (address) {
        return chainId == Constants.MAINNET ? AddressBook.BB_wstETH4626 : AddressBookGoerli.BB_wstETH4626;
    }
}
