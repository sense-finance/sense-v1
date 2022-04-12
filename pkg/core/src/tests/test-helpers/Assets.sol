// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @notice Program error types
library Assets {
    // assets
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    // ctokens
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant cUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;

    // eth
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // protocols
    address public constant COMPOUND_PRICE_FEED = 0x6D2299C48a8dD07a872FDd0F8233924872Ad1071;
    address public constant RARI_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D; // rari's oracle
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant STETHPRICEFEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    address public constant MASTER_PRICE_ORACLE = 0x54Bd48678fdC1Ec2EF832C2d80030E94118CCb4B;

    // fuse f18 olympus pool party
    address public constant OLYMPUS_POOL_PARTY = 0x621579DD26774022F33147D3852ef4E00024b763; // olympus pool party
    address public constant f18DAI = 0x8E4E0257A4759559B4B1AC087fe8d80c63f20D19;
    address public constant f18ETH = 0xFA1057d02A0C1a4885851e3F4fD496Ee7D38F56e;
    address public constant f18USDC = 0x6f95d4d251053483f41c8718C30F4F3C404A8cf2;

    // fuse f156 tribe convex pool
    address public constant TRIBE_CONVEX = 0x07cd53380FE9B2a5E64099591b498c73F0EfaA66; // tribe convex pool
    address public constant f156FRAX3CRV = 0x2ec70d3Ff3FD7ac5c2a72AAA64A398b6CA7428A5;
    address public constant f156cvxFXSFXSf = 0x30916E14C139d65CAfbEEcb3eA525c59df643281;
    address public constant f156CVX = 0x3F4a965Bff126af42FC014c20959c7b857EA4e35;
}
