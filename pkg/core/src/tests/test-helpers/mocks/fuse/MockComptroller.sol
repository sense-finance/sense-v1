// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockComptroller {
    mapping(address => address) public ctokens;
    mapping(address => address) public underlyings;
    uint256 public nonce;

    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
    }

    function _deployMarket(
        bool isCEther,
        bytes calldata constructorData,
        uint256 collateralFactorMantissa
    ) external virtual returns (uint256) {
        (address token, , , , , , , , ) = abi.decode(
            constructorData,
            (address, address, address, string, string, address, bytes, uint256, uint256)
        );
        require(ctokens[token] == address(0));
        ctokens[token] = address(uint160(uint256(keccak256(abi.encodePacked(++nonce, blockhash(block.number))))));
        underlyings[ctokens[token]] = token;
        return 0;
    }

    function _acceptAdmin() external virtual returns (uint256) {
        return 0;
    }

    function cTokensByUnderlying(address token) external virtual returns (address) {
        if (ctokens[token] != address(0)) {
            return ctokens[token];
        }
        return address(0);
    }

    function markets(address token) external virtual returns (Market memory) {
        return Market({ isListed: underlyings[token] != address(0), collateralFactorMantissa: 0 });
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
