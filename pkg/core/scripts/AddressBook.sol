// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// @notice Program error types
library AddressBook {
    // chains
    uint256 public constant MAINNET = 1;
    uint256 public constant GOERLI = 5;
    uint256 public constant FORK = 111;

    // coins
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address public constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address public constant MUSD = 0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;
    address public constant HT = 0x6f259637dcD74C767781E37Bc6133cd6A68aa161;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    // ctokens
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant cBAT = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant cUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant cLINK = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
    address public constant cUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;

    // eth
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // protocols
    address public constant STETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant STETH_CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; // curve stETH

    // price feeds
    address public constant COMPOUND_PRICE_FEED = 0x6D2299C48a8dD07a872FDd0F8233924872Ad1071; // compound
    address public constant RARI_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D; // rari
    address public constant MASTER_PRICE_ORACLE = 0x54Bd48678fdC1Ec2EF832C2d80030E94118CCb4B;
    address public constant STETH_USD_PRICEFEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8; // Chainlink stETH-USD price feed
    address public constant ETH_USD_PRICEFEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH-USD price feed

    // deployed sense contract
    address public constant SPACE_FACTORY_1_2_0 = 0x984682770f1EED90C00cd57B06b151EC12e7c51C;
    address public constant DIVIDER_1_2_0 = 0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0;
    address public constant POOL_MANAGER_1_2_0 = 0xf01eb98de53ed964AC3F786b80ED8ce33f05F417;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant PERIPHERY_1_3_0 = 0xFff11417a58781D3C72083CB45EF54d79Cd02437;
    address public constant PERIPHERY_1_4_0 = 0xaa17633AA5A3Cb56698838561161bdb16Cebb8E3;
    address public constant SENSE_MULTISIG = 0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57;

    // 4626 factories
    address public constant NON_CROP_4626_FACTORY = 0xD28372e7b9904589d05BD257B85FeA40FbD4dF2b;
    address public constant CROP_4626_FACTORY = 0xeDD3B06B7596848E58e5E656e6B4973CD60Be11A;
    address public constant CROPS_4626_FACTORY = 0x93292717B1C0150A68A748C121BE8C3B72dFefb8;

    // sense
    address public constant SENSE_ADMIN_MULTISIG = 0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57;
    address public constant SENSE_MASTER_PRICE_ORACLE = 0x11D341d35BF95654BC7A9db59DBc557cCB4ea101;

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

    // mstable
    address public constant IMUSD = 0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19; // Interest bearing mStable USD (ERC-4626)
    address public constant IMBTC = 0x17d8CBB6Bce8cEE970a4027d1198F6700A7a6c24; // Interest bearing mStable BTC (ERC-4626)
    address public constant RARI_MSTABLE_ORACLE = 0xeb988f5492C86584f8D8f1B8662188D5A9BfE357; // Rari's mStable price oracle
    address public constant CHAINLINK_REGISTRY = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink's Feed Registry

    // fuse core contracts
    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x67Db14E73C2Dce786B5bbBfa4D010dEab4BBFCF9;
    address public constant MASTER_ORACLE_IMPL = 0xb3c8eE7309BE658c186F986388c2377da436D8fb;
    address public constant MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    // euler
    address public constant EULER = 0x27182842E098f60e3D576794A5bFFb0777E025d3; // Euler
    address public constant EULER_MARKETS = 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3; // Euler Markets
    address public constant EULER_USDC = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716;
    address public constant EULER_WSTETH = 0xbd1bd5C956684f7EB79DA40f582cbE1373A1D593;

    // Idle Finance
    address public constant BB_wstETH4626 = 0x79F05f75df6c156B2B98aC1FBfb3637fc1e6f048; // IdleCDO BB Tranche - wstETH4626Adapter
}
