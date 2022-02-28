// 1 -> Mainnet
// 111 -> Local Mainnet fork
// 42161 -> Arbitrum

// For dev scenarios ------------

// ------------------------------------

// For mainnet scenarios ------------

const DIVIDER_CUP = new Map();
DIVIDER_CUP.set("1", "0x0000000000000000000000000000000000000000"); // TODO(launch): real cup address (destination for unclaimed issuance fees)
DIVIDER_CUP.set("111", "0x0000000000000000000000000000000000000000");
// TODO(launch): Arbitrum

COMP_TOKEN = new Map();
COMP_TOKEN.set("1", "0xc00e94cb662c3520282e6f5717214004a7f26888");
COMP_TOKEN.set("111", "0xc00e94cb662c3520282e6f5717214004a7f26888");
// TODO(launch): Arbitrum

const DAI_TOKEN = new Map();
DAI_TOKEN.set("1", "0x6b175474e89094c44da98b954eedeac495271d0f");
DAI_TOKEN.set("111", "0x6b175474e89094c44da98b954eedeac495271d0f");
// TODO(launch): Arbitrum

const CDAI_TOKEN = new Map();
CDAI_TOKEN.set("1", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");
CDAI_TOKEN.set("111", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");
// TODO(launch): Arbitrum

const WETH_TOKEN = new Map();
WETH_TOKEN.set("111", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
// TODO(launch): Arbitrum

const FUSE_POOL_DIR = new Map();
FUSE_POOL_DIR.set("1", "0x835482FE0532f169024d5E9410199369aAD5C77E");
FUSE_POOL_DIR.set("111", "0x835482FE0532f169024d5E9410199369aAD5C77E");
// TODO(launch): Arbitrum

const FUSE_COMPTROLLER_IMPL = new Map();
FUSE_COMPTROLLER_IMPL.set("1", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");
FUSE_COMPTROLLER_IMPL.set("111", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");
// TODO(launch): Arbitrum

const FUSE_CERC20_IMPL = new Map();
FUSE_CERC20_IMPL.set("1", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");
FUSE_CERC20_IMPL.set("111", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");

const MASTER_ORACLE_IMPL = new Map();
MASTER_ORACLE_IMPL.set("1", "0xb3c8ee7309be658c186f986388c2377da436d8fb");
MASTER_ORACLE_IMPL.set("111", "0xb3c8ee7309be658c186f986388c2377da436d8fb");

const MASTER_ORACLE = new Map();
MASTER_ORACLE.set("111", "0x1887118E49e0F4A78Bd71B792a49dE03504A764D");

const COMPOUND_PRICE_FEED = new Map();
COMPOUND_PRICE_FEED.set("1", "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071");
COMPOUND_PRICE_FEED.set("111", "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071");

const INTEREST_RATE_MODEL = new Map();
INTEREST_RATE_MODEL.set("1", "0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7"); // TODO(launch)
INTEREST_RATE_MODEL.set("111", "0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7"); // TODO(launch)

const BALANCER_VAULT = new Map();
BALANCER_VAULT.set("1", "0xBA12222222228d8Ba445958a75a0704d566BF2C8");
BALANCER_VAULT.set("111", "0xBA12222222228d8Ba445958a75a0704d566BF2C8");
// TODO(launch): Arbitrum

exports.COMP_TOKEN = COMP_TOKEN;
exports.DAI_TOKEN = DAI_TOKEN;
exports.CDAI_TOKEN = CDAI_TOKEN;
exports.WETH_TOKEN = WETH_TOKEN;
exports.DIVIDER_CUP = DIVIDER_CUP;
exports.FUSE_POOL_DIR = FUSE_POOL_DIR;
exports.FUSE_COMPTROLLER_IMPL = FUSE_COMPTROLLER_IMPL;
exports.FUSE_CERC20_IMPL = FUSE_CERC20_IMPL;
exports.MASTER_ORACLE_IMPL = MASTER_ORACLE_IMPL;
exports.MASTER_ORACLE = MASTER_ORACLE;
exports.COMPOUND_PRICE_FEED = COMPOUND_PRICE_FEED;
exports.INTEREST_RATE_MODEL = INTEREST_RATE_MODEL;
exports.BALANCER_VAULT = BALANCER_VAULT;
// ------------------------------------