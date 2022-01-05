// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract MockComptroller {
    function _deployMarket(
        bool isCEther,
        bytes calldata constructorData,
        uint256 collateralFactorMantissa
    ) external returns (uint256) {
        return 0;
    }

    function _acceptAdmin() external returns (uint256) {
        return 0;
    }
}
