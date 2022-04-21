const { WETH_TOKEN, WSTETH_TOKEN, MASTER_ORACLE, COMP_TOKEN, F156FRAX3CRV_TOKEN, FRAX3CRV_TOKEN, CONVEX_TOKEN, CRV_TOKEN, TRIBE_CONVEX, REWARDS_DISTRIBUTOR_CVX, REWARDS_DISTRIBUTOR_CRV, CDAI_TOKEN, F18DAI_TOKEN, OLYMPUS_POOL_PARTY } = require("./hardhat.addresses");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");
const ethers = require("ethers");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

// -------------------------------------------------------
//  FOR DEV SCENARIOS
// -------------------------------------------------------
const DEV_SERIES_MATURITIES = [
  // beginning of the week falling between 0 and 1 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 1)
    .startOf("week")
    .unix(),
  // beginning of the week falling between 1 and 2 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 2)
    .startOf("week")
    .unix(),
];
const DEV_TARGETS = [
  { name: "cDAI", tDecimals: 8, uDecimals: 18, guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cETH", tDecimals: 8, uDecimals: 18, guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cWBTC", tDecimals: 18, uDecimals: 18, guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
];

const DEV_CROP_TARGETS = [
  { name: "cropDAI", tDecimals: 8, uDecimals: 18, comptroller: "0x", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cropETH", tDecimals: 8, uDecimals: 18, comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cropWBTC", tDecimals: 18, uDecimals: 18, comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
];

const DEV_ADAPTERS = [
  chainId => ({
    contractName: "MockAdapter",
    target: {
      name: "cUSDC",
      tDecimals: 8,
      uDecimals: 6,
      guard: ethers.utils.parseEther("1"),
      series: DEV_SERIES_MATURITIES,
      crops: false
    },
    underlying: "0x0",
    ifee: ethers.utils.parseEther("0.01"),
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31
    },
  }),
  chainId => ({
    contractName: "MockCropsAdapter",
    target: {
      name: "cUSDT",
      tDecimals: 8,
      uDecimals: 6,
      guard: ethers.utils.parseEther("1"),
      series: DEV_SERIES_MATURITIES,
      crops: true
    },
    underlying: "0x0",
    ifee: ethers.utils.parseEther("0.01"),
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31
    },
  }),
];

const DEV_FACTORIES = [
  chainId => ({
    contractName: "MockFactory",
    oracle: ethers.constants.AddressZero, // oracle address
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    ifee: ethers.utils.parseEther("0.01"),
    mode: 1, // 0 monthly, 1 weekly;
    tilt: 0,
    targets: DEV_TARGETS,
    crops: false,
  }),
  chainId => ({
    contractName: "MockCropsFactory",
    ifee: ethers.utils.parseEther("0.01"),
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    mode: 1, // 0 monthly, 1 weekly;
    oracle: ethers.constants.AddressZero, // oracle address
    tilt: 0,
    targets: DEV_CROP_TARGETS,
    crops: true
  }),
];
// ------------------------------------

// -------------------------------------------------------
//  FOR MAINET SCENARIOS
// -------------------------------------------------------

const CTARGETS = chainId => ([
  { name: "cDAI", address: CDAI_TOKEN.get(chainId), comptroller: "0x", guard: ethers.constants.MaxUint256, series: [] }
]);

const FTARGETS = chainId => ([
  { name: "f8DAI", address: F18DAI_TOKEN.get(chainId), comptroller: OLYMPUS_POOL_PARTY.get(chainId), guard: ethers.constants.MaxUint256, series: [] },
]);

// List of factories to deploy which includes a targets array to indicate,
// for factory, which target adapters to deploy
// (We are currently not deploying any factory)
const MAINNET_FACTORIES = [
  // CFactory example
  chainId => ({
    contractName: "CFactory",
    adapterContract: "CAdapter",
    oracle: MASTER_ORACLE.get(chainId),
    stake: WETH_TOKEN.get(chainId),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000",
    maxm: "33507037",
    ifee: ethers.utils.parseEther("0.0025"),
    mode: 0,
    tilt: 0,
    reward: COMP_TOKEN.get(chainId),
    targets: CTARGETS(chainId),
    crops: false,
  }),
  // FFactory example
  chainId => ({
    contractName: "FFactory",
    adapterContract: "FAdapter",
    oracle: MASTER_ORACLE.get(chainId),
    stake: WETH_TOKEN.get(chainId),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000",
    maxm: "33507037",
    ifee: ethers.utils.parseEther("0.0025"),
    mode: 0,
    tilt: 0,
    targets: FTARGETS(chainId),
    crops: true,
  }),
];

const CUSDC_WSTETH_SERIES_MATURITIES = [
  dayjs
    .utc()
    .week(dayjs().week() + 1)
    .startOf("week")
    .unix(),
];

// List of adapters to deploy directly (without factory)
const MAINNET_ADAPTERS = [
  // WstETHAdapter example
  chainId => ({
    contractName: "WstETHAdapter",
    target: {
      name: "wstETH",
      address: WSTETH_TOKEN.get(chainId),
      guard: ethers.utils.parseEther("1"),
      series: CUSDC_WSTETH_SERIES_MATURITIES
    },
    underlying: WETH_TOKEN.get(chainId),
    ifee: ethers.utils.parseEther("0.01"),
    adapterParams: {
      oracle: MASTER_ORACLE.get(chainId), // oracle address
      stake: WETH_TOKEN.get(chainId),
      stakeSize: ethers.utils.parseEther("0.0025"),
      minm: "0", // 0 weeks
      maxm: "604800", // 1 week
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
    },
  }),
  // FAdapter example
  chainId => ({
    contractName: "FAdapter",
    target: {
      name: "fFRAX3CRV-f-156",
      address: F156FRAX3CRV_TOKEN.get(chainId),
      guard: ethers.utils.parseEther("1"),
      series: CUSDC_WSTETH_SERIES_MATURITIES,
      comptroller: TRIBE_CONVEX.get(chainId),
      rewardsTokens: [CRV_TOKEN.get(chainId), CONVEX_TOKEN.get(chainId)],
      rewardsDistributors: [REWARDS_DISTRIBUTOR_CRV.get(chainId), REWARDS_DISTRIBUTOR_CVX.get(chainId)]
    },
    underlying: FRAX3CRV_TOKEN.get(chainId),
    ifee: ethers.utils.parseEther("0.01"),
    adapterParams: {
      oracle: MASTER_ORACLE.get(chainId), // oracle address
      stake: WETH_TOKEN.get(chainId),
      stakeSize: ethers.utils.parseEther("0.0025"),
      minm: "0", // 0 weeks
      maxm: "604800", // 1 week
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
    },
  }),
];
// ------------------------------------

global.dev = { FACTORIES: DEV_FACTORIES, ADAPTERS: DEV_ADAPTERS };
global.mainnet = { FACTORIES: MAINNET_FACTORIES, ADAPTERS: MAINNET_ADAPTERS };
