// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @notice Program error types
library AddressBook {
    // coins
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address public constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;

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

    // deployed sense contract
    address public constant SPACE_FACTORY_1_2_0 = 0x984682770f1EED90C00cd57B06b151EC12e7c51C;
    address public constant DIVIDER_1_2_0 = 0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0;
    address public constant POOL_MANAGER_1_2_0 = 0xf01eb98de53ed964AC3F786b80ED8ce33f05F417;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    // sense admin
    address public constant SENSE_ADMIN_MULTISIG = 0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57;

    // fuse
    address public constant JUMP_RATE_MODEL = 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7;
    address public constant MASTER_PRICE_ORACLE = 0x54Bd48678fdC1Ec2EF832C2d80030E94118CCb4B;

    // fuse f18 olympus pool party
    address public constant OLYMPUS_POOL_PARTY = 0x621579DD26774022F33147D3852ef4E00024b763; // olympus pool party
    address public constant f18DAI = 0x8E4E0257A4759559B4B1AC087fe8d80c63f20D19;
    address public constant f18ETH = 0xFA1057d02A0C1a4885851e3F4fD496Ee7D38F56e;
    address public constant f18USDC = 0x6f95d4d251053483f41c8718C30F4F3C404A8cf2;

    // fuse f156 tribe convex pool
    address public constant TRIBE_CONVEX = 0x07cd53380FE9B2a5E64099591b498c73F0EfaA66; // tribe convex pool
    address public constant REWARDS_DISTRIBUTOR_CVX = 0x18B9aE8499e560bF94Ef581420c38EC4CfF8559C;
    address public constant REWARDS_DISTRIBUTOR_CRV = 0x65DFbde18D7f12a680480aBf6e17F345d8637829;
    address public constant REWARDS_DISTRIBUTOR_LDO = 0x506Ce4145833E55000cbd4C89AC9ba180647eB5e;
    address public constant REWARDS_DISTRIBUTOR_FXS = 0x30E9A1Bc6A6a478fC32F9ac900C6530Ad3A1616F;

    address public constant f156USDC = 0x88d3557eB6280CC084cA36e425d6BC52d0A04429;
    address public constant f156FRAX3CRV = 0x2ec70d3Ff3FD7ac5c2a72AAA64A398b6CA7428A5;
    address public constant f156cvxFXSFXSf = 0x30916E14C139d65CAfbEEcb3eA525c59df643281;
    address public constant f156CVX = 0x3F4a965Bff126af42FC014c20959c7b857EA4e35;
}
