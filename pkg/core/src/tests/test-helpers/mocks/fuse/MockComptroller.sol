// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

contract MockComptroller {
    struct Market {
        bool isListed;
        uint collateralFactorMantissa;
    }

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

    function cTokensByUnderlying(address) external virtual returns (address) {
        return address(1337);
    }

    function markets(address) external virtual returns (Market memory) {
        return Market({ isListed: true, collateralFactorMantissa: 1 });
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
