const {
  WETH_TOKEN,
  WSTETH_TOKEN,
  MASTER_ORACLE,
  COMP_TOKEN,
  F156FRAX3CRV_TOKEN,
  FRAX3CRV_TOKEN,
  CONVEX_TOKEN,
  CRV_TOKEN,
  TRIBE_CONVEX,
  REWARDS_DISTRIBUTOR_CVX,
  REWARDS_DISTRIBUTOR_CRV,
  CDAI_TOKEN,
} = require("./hardhat.addresses");
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

const NON_CROP = 0;
const CROP = 1;
const CROPS = 2;

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
  {
    name: "cDAI",
    tDecimals: 8,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cETH",
    tDecimals: 8,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cWBTC",
    tDecimals: 18,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
];

const DEV_CROP_TARGETS = [
  {
    name: "cropDAI",
    tDecimals: 8,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cropETH",
    tDecimals: 8,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cropWBTC",
    tDecimals: 18,
    uDecimals: 18,
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
];

const DEV_CROPS_TARGETS = [
  {
    name: "cropsDAI",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cropsETH",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "cropsWBTC",
    tDecimals: 18,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
];

const DEV_4626_TARGETS = [
  {
    name: "crop4626DAI",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "crop4626ETH",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "crop4626WBTC",
    tDecimals: 18,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
];

const DEV_4626_CROPS_TARGETS = [
  {
    name: "crops4626DAI",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "crops4626ETH",
    tDecimals: 8,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
  {
    name: "crops4626WBTC",
    tDecimals: 18,
    uDecimals: 18,
    comptroller: "0x07cd53380FE9B2a5E64099591b498c73F0EfaA66",
    guard: ethers.constants.MaxUint256,
    series: DEV_SERIES_MATURITIES,
  },
];

const DEV_ADAPTERS = [
  () => ({
    contractName: "MockAdapter",
    target: {
      name: "cUSDC",
      tDecimals: 8,
      uDecimals: 6,
      guard: ethers.utils.parseEther("100000"),
      series: DEV_SERIES_MATURITIES,
    },
    underlying: "0x0",
    ifee: ethers.utils.parseEther("0.01"),
    rType: NON_CROP,
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
    },
  }),
  () => ({
    contractName: "MockCropAdapter",
    target: {
      name: "cBAT",
      tDecimals: 8,
      uDecimals: 6,
      guard: ethers.utils.parseEther("100000"),
      series: DEV_SERIES_MATURITIES,
    },
    underlying: "0x0",
    ifee: ethers.utils.parseEther("0.01"),
    rType: CROP,
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
    },
  }),
  () => ({
    contractName: "MockCropsAdapter",
    target: {
      name: "cUSDT",
      tDecimals: 8,
      uDecimals: 6,
      guard: ethers.utils.parseEther("100000"),
      series: DEV_SERIES_MATURITIES,
    },
    underlying: "0x0",
    ifee: ethers.utils.parseEther("0.01"),
    rType: CROPS,
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
    },
  }),
];

const DEV_FACTORIES = [
  () => ({
    contractName: "MockFactory",
    oracle: ethers.constants.AddressZero, // oracle address
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    ifee: ethers.utils.parseEther("0.01"),
    mode: 1, // 0 monthly, 1 weekly;
    rType: NON_CROP,
    tilt: 0,
    targets: DEV_TARGETS,
    is4626Target: false,
    guard: ethers.utils.parseEther("100000"),
  }),
  () => ({
    contractName: "MockCropFactory",
    oracle: ethers.constants.AddressZero, // oracle address
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    ifee: ethers.utils.parseEther("0.01"),
    mode: 1, // 0 monthly, 1 weekly;
    rType: CROP,
    tilt: 0,
    targets: DEV_CROP_TARGETS,
    is4626Target: false,
    guard: ethers.utils.parseEther("100000"),
  }),
  () => ({
    contractName: "MockCropsFactory",
    ifee: ethers.utils.parseEther("0.01"),
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    mode: 1, // 0 monthly, 1 weekly;
    rType: CROPS,
    oracle: ethers.constants.AddressZero, // oracle address
    tilt: 0,
    targets: DEV_CROPS_TARGETS,
    is4626Target: false,
    guard: ethers.utils.parseEther("100000"),
  }),
  () => ({
    contractName: "Mock4626CropFactory",
    oracle: ethers.constants.AddressZero, // oracle address
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    ifee: ethers.utils.parseEther("0.01"),
    mode: 1, // 0 monthly, 1 weekly;
    rType: CROP,
    tilt: 0,
    targets: DEV_4626_TARGETS,
    is4626Target: true,
    guard: ethers.utils.parseEther("100000"),
  }),
  () => ({
    contractName: "Mock4626CropsFactory",
    ifee: ethers.utils.parseEther("0.01"),
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    mode: 1, // 0 monthly, 1 weekly;
    rType: CROPS,
    oracle: ethers.constants.AddressZero, // oracle address
    tilt: 0,
    targets: DEV_4626_CROPS_TARGETS,
    is4626Target: true,
    guard: ethers.utils.parseEther("100000"),
  }),
];
// ------------------------------------

// -------------------------------------------------------
//  FOR MAINET SCENARIOS
// -------------------------------------------------------

const CTARGETS = chainId => [
  {
    name: "cDAI",
    address: CDAI_TOKEN.get(chainId),
    comptroller: "0x",
    guard: ethers.constants.MaxUint256,
    series: [],
  },
];

// const FTARGETS = chainId => [
//   {
//     name: "f8DAI",
//     address: F18DAI_TOKEN.get(chainId),
//     comptroller: OLYMPUS_POOL_PARTY.get(chainId),
//     guard: ethers.constants.MaxUint256,
//     series: [],
//   },
// ];

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
    rType: CROP,
    tilt: 0,
    reward: COMP_TOKEN.get(chainId),
    targets: CTARGETS(chainId),
    guard: ethers.utils.parseEther("100000"),
  }),
  // FFactory example
  // NOTE: commenting the FFactory since since exceeds the contract size
  // and we are not currently using it
  // chainId => ({
  //   contractName: "FFactory",
  //   adapterContract: "FAdapter",
  //   oracle: MASTER_ORACLE.get(chainId),
  //   stake: WETH_TOKEN.get(chainId),
  //   stakeSize: ethers.utils.parseEther("0.25"),
  //   minm: "1814000",
  //   maxm: "33507037",
  //   ifee: ethers.utils.parseEther("0.0025"),
  //   mode: 0,
  //   rType: CROPS,
  //   tilt: 0,
  //   targets: FTARGETS(chainId),
  //   guard: ethers.utils.parseEther("100000"),
  // }),
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
      series: CUSDC_WSTETH_SERIES_MATURITIES,
    },
    ifee: ethers.utils.parseEther("0.01"),
    rType: NON_CROP,
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
      rewardsDistributors: [REWARDS_DISTRIBUTOR_CRV.get(chainId), REWARDS_DISTRIBUTOR_CVX.get(chainId)],
    },
    underlying: FRAX3CRV_TOKEN.get(chainId),
    ifee: ethers.utils.parseEther("0.01"),
    rType: CROPS,
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

exports.NON_CROP = NON_CROP;
exports.CROP = CROP;
exports.CROPS = CROPS;
