// Balancer
const BALANCER_VAULT = new Map();
BALANCER_VAULT.set("1", "0xBA12222222228d8Ba445958a75a0704d566BF2C8");
BALANCER_VAULT.set("5", "0x1aB16CB0cb0e5520e0C081530C679B2e846e4D37");
BALANCER_VAULT.set("111", "0xBA12222222228d8Ba445958a75a0704d566BF2C8");

// Compound
const COMP_TOKEN = new Map();
COMP_TOKEN.set("1", "0xc00e94cb662c3520282e6f5717214004a7f26888");
COMP_TOKEN.set("111", "0xc00e94cb662c3520282e6f5717214004a7f26888");

const CDAI_TOKEN = new Map();
CDAI_TOKEN.set("1", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");
CDAI_TOKEN.set("5", "0x8D170266d009d720F3286D8FBe8BAc40217f4aE9");
CDAI_TOKEN.set("111", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");

const CUSDC_TOKEN = new Map();
CUSDC_TOKEN.set("1", "0x39AA39c021dfbaE8faC545936693aC917d5E7563");
CUSDC_TOKEN.set("5", "0x5A13CC452Bb4225fe1c1005f965C27be05aeF7C5");
CUSDC_TOKEN.set("111", "0x39AA39c021dfbaE8faC545936693aC917d5E7563");

const CUSDT_TOKEN = new Map();
CUSDT_TOKEN.set("1", "0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9");
CUSDT_TOKEN.set("5", "0xF3A0C5F5Ae311e824DeFDcf9DaDFBd6a7a404DB8");
CUSDT_TOKEN.set("111", "0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9");

// Euler
const EULER = new Map();
EULER.set("1", "0x27182842E098f60e3D576794A5bFFb0777E025d3");
EULER.set("111", "0x27182842E098f60e3D576794A5bFFb0777E025d3");

const EULER_MARKETS = new Map();
EULER_MARKETS.set("1", "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3");
EULER_MARKETS.set("111", "0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3");

const EULER_USDC = new Map();
EULER_USDC.set("1", "0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716");
EULER_USDC.set("111", "0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716");

const EULER_WSTETH = new Map();
EULER_WSTETH.set("1", "0xbd1bd5C956684f7EB79DA40f582cbE1373A1D593");
EULER_WSTETH.set("111", "0xbd1bd5C956684f7EB79DA40f582cbE1373A1D593");

// Fuse, Rari
const TRIBE_CONVEX = new Map();
TRIBE_CONVEX.set("1", "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66");
TRIBE_CONVEX.set("111", "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66");

const REWARDS_DISTRIBUTOR_CVX = new Map();
REWARDS_DISTRIBUTOR_CVX.set("1", "0x18B9aE8499e560bF94Ef581420c38EC4CfF8559C");
REWARDS_DISTRIBUTOR_CVX.set("111", "0x18B9aE8499e560bF94Ef581420c38EC4CfF8559C");

const REWARDS_DISTRIBUTOR_CRV = new Map();
REWARDS_DISTRIBUTOR_CRV.set("1", "0xd533a949740bb3306d119cc777fa900ba034cd52");
REWARDS_DISTRIBUTOR_CRV.set("111", "0xd533a949740bb3306d119cc777fa900ba034cd52");

const FUSE_POOL_DIR = new Map();
FUSE_POOL_DIR.set("1", "0x835482FE0532f169024d5E9410199369aAD5C77E");
FUSE_POOL_DIR.set("111", "0x835482FE0532f169024d5E9410199369aAD5C77E");

const FUSE_COMPTROLLER_IMPL = new Map();
FUSE_COMPTROLLER_IMPL.set("1", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");
FUSE_COMPTROLLER_IMPL.set("111", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");

const FUSE_CERC20_IMPL = new Map();
FUSE_CERC20_IMPL.set("1", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");
FUSE_CERC20_IMPL.set("111", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");

const MASTER_ORACLE_IMPL = new Map();
MASTER_ORACLE_IMPL.set("1", "0xb3c8ee7309be658c186f986388c2377da436d8fb");
MASTER_ORACLE_IMPL.set("111", "0xb3c8ee7309be658c186f986388c2377da436d8fb");

const MASTER_ORACLE = new Map();
MASTER_ORACLE.set("1", "0x1887118E49e0F4A78Bd71B792a49dE03504A764D");
MASTER_ORACLE.set("111", "0x1887118E49e0F4A78Bd71B792a49dE03504A764D");

const MSTABLE_RARI_ORACLE = new Map();
MSTABLE_RARI_ORACLE.set("1", "0xeb988f5492C86584f8D8f1B8662188D5A9BfE357");
MSTABLE_RARI_ORACLE.set("111", "0xeb988f5492C86584f8D8f1B8662188D5A9BfE357");

const COMPOUND_PRICE_FEED = new Map();
COMPOUND_PRICE_FEED.set("1", "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071");
COMPOUND_PRICE_FEED.set("111", "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071");

const INTEREST_RATE_MODEL = new Map();
INTEREST_RATE_MODEL.set("1", "0x640dce7c7c6349e254b20eccfa2bb902b354c317");
INTEREST_RATE_MODEL.set("111", "0x640dce7c7c6349e254b20eccfa2bb902b354c317");

// Lido Finance
const WETH_TOKEN = new Map();
WETH_TOKEN.set("1", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
WETH_TOKEN.set("5", "0xC027849ac78202A17A872021Bd0271DA5df04168");
WETH_TOKEN.set("111", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");

const WSTETH_TOKEN = new Map();
WSTETH_TOKEN.set("1", "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0");
WSTETH_TOKEN.set("111", "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0");

const STETH_TOKEN = new Map();
STETH_TOKEN.set("1", "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84");
STETH_TOKEN.set("111", "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84");

// Morpho
const MORPHO_TOKEN = new Map();
MORPHO_TOKEN.set("1", "0x9994E35Db50125E0DF82e4c2dde62496CE330999");
MORPHO_TOKEN.set("111", "0x9994E35Db50125E0DF82e4c2dde62496CE330999");

const MORPHO_USDC = new Map();
MORPHO_USDC.set("1", "0xa5269a8e31b93ff27b887b56720a25f844db0529");
MORPHO_USDC.set("5", "0x49b437881c015Ae269726aa3C8E5Cd27E6CaE06D");
MORPHO_USDC.set("111", "0xa5269a8e31b93ff27b887b56720a25f844db0529");

const MORPHO_DAI = new Map();
MORPHO_DAI.set("1", "0x36f8d0d0573ae92326827c4a82fe4ce4c244cab6");
MORPHO_DAI.set("5", "0x1e1157Cee9A5a0E36A3936E7e91476d22283f640");
MORPHO_DAI.set("111", "0x36f8d0d0573ae92326827c4a82fe4ce4c244cab6");

const MORPHO_USDT = new Map();
MORPHO_USDT.set("1", "0xafe7131a57e44f832cb2de78ade38cad644aac2f");
MORPHO_USDT.set("5", "0x897Aec31aB73106E4aD10E6F85a68EdCfe35fcE2");
MORPHO_USDT.set("111", "0xafe7131a57e44f832cb2de78ade38cad644aac2f");

// Idle Finance
const BB_wstETH4626 = new Map();
BB_wstETH4626.set("1", "0x79F05f75df6c156B2B98aC1FBfb3637fc1e6f048");
BB_wstETH4626.set("111", "0x79F05f75df6c156B2B98aC1FBfb3637fc1e6f048");

// Angle
const sanFRAX_EUR_Wrapper = new Map();
sanFRAX_EUR_Wrapper.set("1", "0x14244978b1CC189324C3e35685D6Ae2F632e9846");
sanFRAX_EUR_Wrapper.set("5", "0x5A13CC452Bb4225fe1c1005f965C27be05aeF7C5"); // cUSDC
sanFRAX_EUR_Wrapper.set("111", "0x14244978b1CC189324C3e35685D6Ae2F632e9846");

const ANGLE = new Map();
ANGLE.set("1", "0x31429d1856aD1377A8A0079410B297e1a9e214c2");
ANGLE.set("111", "0x31429d1856aD1377A8A0079410B297e1a9e214c2");
ANGLE.set("5", "0x6b175474e89094c44da98b954eedeac495271d0f"); // DAI

const FRAX = new Map();
FRAX.set("1", "0x853d955acef822db058eb8505911ed77f175b99e");
FRAX.set("5", "0xc4723445bD201f685A8128DC2D602DD86B696E22"); // USDC
FRAX.set("111", "0x853d955acef822db058eb8505911ed77f175b99e");

// mStable
const IMUSD_TOKEN = new Map();
IMUSD_TOKEN.set("1", "0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19");
IMUSD_TOKEN.set("111", "0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19");

const MUSD_TOKEN = new Map();
MUSD_TOKEN.set("1", "0xe2f2a5C287993345a840Db3B0845fbC70f5935a5");
MUSD_TOKEN.set("111", "0xe2f2a5C287993345a840Db3B0845fbC70f5935a5");

const IMBTC_TOKEN = new Map();
IMBTC_TOKEN.set("1", "0x17d8CBB6Bce8cEE970a4027d1198F6700A7a6c24");
IMBTC_TOKEN.set("111", "0x17d8CBB6Bce8cEE970a4027d1198F6700A7a6c24");

// Olympus
const F18DAI_TOKEN = new Map();
F18DAI_TOKEN.set("1", "0x8E4E0257A4759559B4B1AC087fe8d80c63f20D19");
F18DAI_TOKEN.set("111", "0x8E4E0257A4759559B4B1AC087fe8d80c63f20D19");

const OLYMPUS_POOL_PARTY = new Map();
OLYMPUS_POOL_PARTY.set("1", "0x621579DD26774022F33147D3852ef4E00024b763");
OLYMPUS_POOL_PARTY.set("111", "0x621579DD26774022F33147D3852ef4E00024b763");

const F156FRAX3CRV_TOKEN = new Map();
F156FRAX3CRV_TOKEN.set("1", "0x2ec70d3Ff3FD7ac5c2a72AAA64A398b6CA7428A5");
F156FRAX3CRV_TOKEN.set("111", "0x2ec70d3Ff3FD7ac5c2a72AAA64A398b6CA7428A5");

const FRAX3CRV_TOKEN = new Map();
FRAX3CRV_TOKEN.set("1", "0xd632f22692fac7611d2aa1c0d552930d43caed3b");
FRAX3CRV_TOKEN.set("111", "0xd632f22692fac7611d2aa1c0d552930d43caed3b");

const CONVEX_TOKEN = new Map();
CONVEX_TOKEN.set("1", "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b");
CONVEX_TOKEN.set("111", "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b");

const CRV_TOKEN = new Map();
CRV_TOKEN.set("1", "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b");
CRV_TOKEN.set("111", "0x4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b");

///// SENSE START //////

// Core
const DIVIDER_1_2_0 = new Map();
DIVIDER_1_2_0.set("1", "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0");
DIVIDER_1_2_0.set("5", "0x09B10E45A912BcD4E80a8A3119f0cfCcad1e1f12");
DIVIDER_1_2_0.set("111", "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0");

const PERIPHERY_1_3_0 = new Map();
PERIPHERY_1_3_0.set("1", "0xFff11417a58781D3C72083CB45EF54d79Cd02437");
PERIPHERY_1_3_0.set("111", "0xFff11417a58781D3C72083CB45EF54d79Cd02437");

const PERIPHERY_1_4_0 = new Map();
PERIPHERY_1_4_0.set("1", "0xaa17633AA5A3Cb56698838561161bdb16Cebb8E3");
PERIPHERY_1_4_0.set("5", "0x4bCBA1316C95B812cC014CA18C08971Ce1C10861");
PERIPHERY_1_4_0.set("111", "0xaa17633AA5A3Cb56698838561161bdb16Cebb8E3");

// Fuse
const POOL_MANAGER_1_2_0 = new Map();
POOL_MANAGER_1_2_0.set("1", "0xf01eb98de53ed964AC3F786b80ED8ce33f05F417");
POOL_MANAGER_1_2_0.set("111", "0xf01eb98de53ed964AC3F786b80ED8ce33f05F417");

// Space
const SPACE_FACTORY_1_2_0 = new Map();
SPACE_FACTORY_1_2_0.set("1", "0x984682770f1EED90C00cd57B06b151EC12e7c51C");
SPACE_FACTORY_1_2_0.set("111", "0x984682770f1EED90C00cd57B06b151EC12e7c51C");

const SPACE_FACTORY_1_3_0 = new Map();
SPACE_FACTORY_1_3_0.set("1", "0x9e629751b3FE0b030C219e567156adCB70ad5541");
SPACE_FACTORY_1_3_0.set("5", "0x1621cb1a1A4BA17aF0aD62c6142A7389C81e831D");
SPACE_FACTORY_1_3_0.set("111", "0x9e629751b3FE0b030C219e567156adCB70ad5541");

const QUERY_PROCESSOR = new Map();
QUERY_PROCESSOR.set("1", "0xcbe8c43a6e3be093489b5b1bff2e851d01d451f6");
QUERY_PROCESSOR.set("111", "0xcbe8c43a6e3be093489b5b1bff2e851d01d451f6");

// Factories
const NON_CROP_4626_FACTORY = new Map();
NON_CROP_4626_FACTORY.set("1", "0xeE15E6c4c6dacBA162E6BD8C6C7185049BeBa212");
NON_CROP_4626_FACTORY.set("5", "0x03A206Ad50BA7862473AD88c236E851695F43027");
NON_CROP_4626_FACTORY.set("111", "0xeE15E6c4c6dacBA162E6BD8C6C7185049BeBa212");

const CROP_4626_FACTORY = new Map();
CROP_4626_FACTORY.set("1", "0xeDD3B06B7596848E58e5E656e6B4973CD60Be11A");
CROP_4626_FACTORY.set("5", "0x27F6f7E23b4D77FE9aD7f9A0756a9b40bddE32c9"); // Mock ERC4626 Crop Factory
CROP_4626_FACTORY.set("111", "0xeDD3B06B7596848E58e5E656e6B4973CD60Be11A");

const CROPS_4626_FACTORY = new Map();
CROPS_4626_FACTORY.set("1", "0x93292717B1C0150A68A748C121BE8C3B72dFefb8");
CROPS_4626_FACTORY.set("111", "0x93292717B1C0150A68A748C121BE8C3B72dFefb8");

const CROP_FACTORY = new Map();
CROP_FACTORY.set("5", "0xDbE7deE84f9A32E5b2CA8215ea6Ad85b4c293655"); // MockCropFactory

// Adapters
const WSTETH_OWNABLE_ADAPTER = new Map();
WSTETH_OWNABLE_ADAPTER.set("1", "0x66E1AD7cDa66A0B291aEC63f3dBD8cB9eAF76680");
WSTETH_OWNABLE_ADAPTER.set("111", "0x66E1AD7cDa66A0B291aEC63f3dBD8cB9eAF76680");

const OWNABLE_MAUSDC_ADAPTER = new Map();
OWNABLE_MAUSDC_ADAPTER.set("1", "0x529c90E6d3a1AedaB9B3011196C495439D23b893");
OWNABLE_MAUSDC_ADAPTER.set("111", "0x529c90E6d3a1AedaB9B3011196C495439D23b893");

const OWNABLE_MAUSDT_ADAPTER = new Map();
OWNABLE_MAUSDT_ADAPTER.set("1", "0x8c5e7301a012DC677DD7DaD97aE44032feBCD0FD");
OWNABLE_MAUSDT_ADAPTER.set("111", "0x8c5e7301a012DC677DD7DaD97aE44032feBCD0FD");

const CUSDC_OWNABLE_ADAPTER = new Map();
CUSDC_OWNABLE_ADAPTER.set("5", "0x7b6da076144b0a9cf0cddf908f605924d9e0a180");

const CUSDT_OWNABLE_ADAPTER = new Map();
CUSDT_OWNABLE_ADAPTER.set("5", "0xa4f9b98c1Bce4b0A9Bbe5dcBf17dc64a55C79477");

const CDAI_OWNABLE_ADAPTER = new Map();
CDAI_OWNABLE_ADAPTER.set("5", "0xA1Dc1E9C1a2a087874634cc7D0395658A741027c");

const CUSDC_ADAPTER = new Map();
CUSDC_ADAPTER.set("5", "0x3de1bEE160898B204D470F41a82d9Bd066CfE6a6");

const CUSDT_ADAPTER = new Map();
CUSDT_ADAPTER.set("5", "0xAFe0235D674Be9A63316eAd6e6Cd5E3FA9047b43");

const CDAI_ADAPTER = new Map();
CDAI_ADAPTER.set("5", "0xfcC6ba91745F0a81f2334D7608c7D2B72c9E8e84");

const BB_wstETH4626_ADAPTER = new Map();
BB_wstETH4626_ADAPTER.set("1", "0x86c55BFFb64f8fCC8beA33F3176950FDD0fb160D");
BB_wstETH4626_ADAPTER.set("111", "0x86c55BFFb64f8fCC8beA33F3176950FDD0fb160D");

const sanFRAX_EUR_Wrapper_ADAPTER = new Map();
sanFRAX_EUR_Wrapper_ADAPTER.set("1", "0x2E1e993424cb2D3Eb42C87D32bfd51B23854022D");
sanFRAX_EUR_Wrapper_ADAPTER.set("111", "0x2E1e993424cb2D3Eb42C87D32bfd51B23854022D");

// Sense-related addresses
const SENSE_MULTISIG = new Map();
SENSE_MULTISIG.set("1", "0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57");
SENSE_MULTISIG.set("5", "0xf13519734649f7464e5be4aa91987a35594b2b16");
SENSE_MULTISIG.set("111", "0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57");

const DIVIDER_CUP = new Map();
DIVIDER_CUP.set("1", "0x6C4f62b3187bC7e8A8f948Bb50ABec694719D8d3"); // Sense multisig
DIVIDER_CUP.set("111", "0x6C4f62b3187bC7e8A8f948Bb50ABec694719D8d3");

const OZ_RELAYER = new Map();
OZ_RELAYER.set("1", "0xe09fe5acb74c1d98507f87494cf6adebd3b26b1e");
OZ_RELAYER.set("5", "0xdd843f67d02150bf6fa0a7733673d2144f88e5b6");
OZ_RELAYER.set("111", "0xe09fe5acb74c1d98507f87494cf6adebd3b26b1e");

// RLV
const ROLLER_UTILS = new Map();
ROLLER_UTILS.set("1", "0xb6f7643fd0831eda3BAbe20EE9c98DA4D473807e");
ROLLER_UTILS.set("5", "0xd56804E048aC4EEfDA5F1cc99079f154150bD727");
ROLLER_UTILS.set("111", "0xb6f7643fd0831eda3BAbe20EE9c98DA4D473807e");

const ROLLER_PERIPHERY = new Map();
ROLLER_PERIPHERY.set("1", "0xF3244CDCC765B15CbE1479c564f5fa31125d4FC3");
ROLLER_PERIPHERY.set("5", "0x71C93f0290119B1Dbd037e0B301d14538AF35Ab9");
ROLLER_PERIPHERY.set("111", "0xF3244CDCC765B15CbE1479c564f5fa31125d4FC3");

const RLV_FACTORY = new Map();
RLV_FACTORY.set("1", "0x3b0f35bdd6da9e3b8513c58af8fdf231f60232e5");
RLV_FACTORY.set("5", "0x755E3FB62b8224AfCdF3cAb9816b1D76F0C81838");
RLV_FACTORY.set("111", "0x3b0f35bdd6da9e3b8513c58af8fdf231f60232e5");

// Oracle
const SENSE_MASTER_ORACLE = new Map();
SENSE_MASTER_ORACLE.set("1", "0x11D341d35BF95654BC7A9db59DBc557cCB4ea101");
SENSE_MASTER_ORACLE.set("5", "0xB3e70779c1d1f2637483A02f1446b211fe4183Fa");
SENSE_MASTER_ORACLE.set("111", "0x11D341d35BF95654BC7A9db59DBc557cCB4ea101");

// Faucet
const MULTIMINT = new Map();
MULTIMINT.set("5", "0xe318c4014330a84e09f08ed5556e2fa6a2fc8dcc");

////// SENSE END //////

// Tokens
const DAI_TOKEN = new Map();
DAI_TOKEN.set("1", "0x6b175474e89094c44da98b954eedeac495271d0f");
DAI_TOKEN.set("5", "0x436f3D3f1e0B7a2335594b57670c7A05Bc5F0dc6");
DAI_TOKEN.set("111", "0x6b175474e89094c44da98b954eedeac495271d0f");

const USDC_TOKEN = new Map();
USDC_TOKEN.set("5", "0xc4723445bD201f685A8128DC2D602DD86B696E22");

const USDT_TOKEN = new Map();
USDT_TOKEN.set("5", "0xB209E94E9216331af1158E8588dD69e0a88eA2Da");

const REWARD_TOKEN = new Map();
REWARD_TOKEN.set("5", "0x59DB5BaddEa0E6660cAD350E69451ECDC5Bff070");

// Misc
const CHAINS = {
  MAINNET: "1",
  GOERLI: "5",
  HARDHAT: "111",
  ARBITRUM: "42161",
};
const VERIFY_CHAINS = [CHAINS.MAINNET, CHAINS.GOERLI, CHAINS.ARBITRUM];

//////////// EXPORTS //////////////

// Balancer
exports.BALANCER_VAULT = BALANCER_VAULT;

// Compound
exports.COMPOUND_PRICE_FEED = COMPOUND_PRICE_FEED;
exports.INTEREST_RATE_MODEL = INTEREST_RATE_MODEL;
exports.COMP_TOKEN = COMP_TOKEN;
exports.CDAI_TOKEN = CDAI_TOKEN;
exports.CUSDC_TOKEN = CUSDC_TOKEN;
exports.CUSDT_TOKEN = CUSDT_TOKEN;

// Euler
exports.EULER = EULER;
exports.EULER_MARKETS = EULER_MARKETS;
exports.EULER_USDC = EULER_USDC;
exports.EULER_WSTETH = EULER_WSTETH;

// Fuse, Rari
exports.FUSE_POOL_DIR = FUSE_POOL_DIR;
exports.FUSE_COMPTROLLER_IMPL = FUSE_COMPTROLLER_IMPL;
exports.FUSE_CERC20_IMPL = FUSE_CERC20_IMPL;
exports.TRIBE_CONVEX = TRIBE_CONVEX;
exports.CONVEX_TOKEN = CONVEX_TOKEN;
exports.CRV_TOKEN = CRV_TOKEN;
exports.REWARDS_DISTRIBUTOR_CVX = REWARDS_DISTRIBUTOR_CVX;
exports.REWARDS_DISTRIBUTOR_CRV = REWARDS_DISTRIBUTOR_CRV;
exports.MSTABLE_RARI_ORACLE = MSTABLE_RARI_ORACLE;
exports.MASTER_ORACLE_IMPL = MASTER_ORACLE_IMPL;
exports.MASTER_ORACLE = MASTER_ORACLE;
exports.RARI_ORACLE = MASTER_ORACLE;

// Lido Finance
exports.WETH_TOKEN = WETH_TOKEN;
exports.WSTETH_TOKEN = WSTETH_TOKEN;
exports.STETH_TOKEN = STETH_TOKEN;

// Morpho
exports.MORPHO_TOKEN = MORPHO_TOKEN;
exports.MORPHO_USDC = MORPHO_USDC;
exports.MORPHO_DAI = MORPHO_DAI;
exports.MORPHO_USDT = MORPHO_USDT;

// Idle Finance
exports.BB_wstETH4626 = BB_wstETH4626;

// Angle
exports.FRAX = FRAX;
exports.sanFRAX_EUR_Wrapper = sanFRAX_EUR_Wrapper;
exports.ANGLE = ANGLE;

// mStable
exports.MUSD_TOKEN = MUSD_TOKEN;
exports.IMUSD_TOKEN = IMUSD_TOKEN;
exports.IMBTC_TOKEN = IMBTC_TOKEN;

// Olympus
exports.OLYMPUS_POOL_PARTY = OLYMPUS_POOL_PARTY;
exports.F18DAI_TOKEN = F18DAI_TOKEN;
exports.F156FRAX3CRV_TOKEN = F156FRAX3CRV_TOKEN;
exports.FRAX3CRV_TOKEN = FRAX3CRV_TOKEN;

// Sense
exports.DIVIDER_CUP = DIVIDER_CUP;
exports.SPACE_FACTORY_1_3_0 = SPACE_FACTORY_1_3_0;
exports.OZ_RELAYER = OZ_RELAYER;
exports.SENSE_MULTISIG = SENSE_MULTISIG;
exports.NON_CROP_4626_FACTORY = NON_CROP_4626_FACTORY;
exports.CROP_4626_FACTORY = CROP_4626_FACTORY;
exports.CROPS_4626_FACTORY = CROPS_4626_FACTORY;
exports.CROP_FACTORY = CROP_FACTORY;
exports.SPACE_FACTORY_1_2_0 = SPACE_FACTORY_1_2_0;
exports.DIVIDER_1_2_0 = DIVIDER_1_2_0;
exports.POOL_MANAGER_1_2_0 = POOL_MANAGER_1_2_0;
exports.PERIPHERY_1_3_0 = PERIPHERY_1_3_0;
exports.PERIPHERY_1_4_0 = PERIPHERY_1_4_0;
exports.QUERY_PROCESSOR = QUERY_PROCESSOR;
exports.ROLLER_PERIPHERY = ROLLER_PERIPHERY;
exports.RLV_FACTORY = RLV_FACTORY;
exports.ROLLER_UTILS = ROLLER_UTILS;
exports.SENSE_MASTER_ORACLE = SENSE_MASTER_ORACLE;
exports.WSTETH_OWNABLE_ADAPTER = WSTETH_OWNABLE_ADAPTER;
exports.OWNABLE_MAUSDC_ADAPTER = OWNABLE_MAUSDC_ADAPTER;
exports.OWNABLE_MAUSDT_ADAPTER = OWNABLE_MAUSDT_ADAPTER;
exports.CUSDC_OWNABLE_ADAPTER = CUSDC_OWNABLE_ADAPTER;
exports.CUSDT_OWNABLE_ADAPTER = CUSDT_OWNABLE_ADAPTER;
exports.CDAI_OWNABLE_ADAPTER = CDAI_OWNABLE_ADAPTER;
exports.CUSDC_ADAPTER = CUSDC_ADAPTER;
exports.CUSDT_ADAPTER = CUSDT_ADAPTER;
exports.CDAI_ADAPTER = CDAI_ADAPTER;
exports.BB_wstETH4626_ADAPTER = BB_wstETH4626_ADAPTER;
exports.sanFRAX_EUR_Wrapper_ADAPTER = sanFRAX_EUR_Wrapper_ADAPTER;
exports.MULTIMINT = MULTIMINT;

// Tokens
exports.DAI_TOKEN = DAI_TOKEN;
exports.USDC_TOKEN = USDC_TOKEN;
exports.USDT_TOKEN = USDT_TOKEN;
exports.REWARD_TOKEN = REWARD_TOKEN;

// Misc
exports.CHAINS = CHAINS;
exports.VERIFY_CHAINS = VERIFY_CHAINS;
exports.VERIFY_CHAINS = VERIFY_CHAINS;

// ------------------------------------
