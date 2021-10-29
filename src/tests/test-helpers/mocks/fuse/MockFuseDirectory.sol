// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract MockFuseDirectory {
    address public comptroller;

    constructor(address _comptroller) {
        comptroller = _comptroller;
    }

    function deployPool(
        string memory name,
        address implementation,
        bool enforceWhitelist,
        uint256 closeFactor,
        uint256 liquidationIncentive,
        address priceOracle
    ) external returns (uint256, address) {
        return (0, comptroller);
    }
}