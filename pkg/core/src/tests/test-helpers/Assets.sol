// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @notice Program error types
library Assets {
    // assets
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    // ctokens
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    // eth
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // protocols
    address public constant RARI_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D; // rari's oracle
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
}
