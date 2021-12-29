// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract MockComptroller {
    function _deployMarket(
        bool isCEther,
        bytes calldata constructorData,
        uint256 collateralFactorMantissa
    ) external virtual returns (uint256) {
        return 0;
    }

    function _acceptAdmin() external virtual returns (uint256) {
        return 0;
    }
}

contract MockComptrollerRejectAdmin is MockComptroller {
    function _acceptAdmin() external override returns (uint256) {
        return 1;
    }
}

contract MockComptrollerFailAddMarket is MockComptroller {
    function _deployMarket(
        bool isCEther,
        bytes calldata constructorData,
        uint256 collateralFactorMantissa
    ) external override returns (uint256) {
        return 1;
    }
}
