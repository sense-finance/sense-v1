const {
  COMP_TOKEN,
  COMPOUND_PRICE_FEED,
  WETH_TOKEN,
  CUSDC_TOKEN,
  WSTETH_TOKEN,
  MASTER_ORACLE_IMPL,
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
  { name: "cDAI", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cETH", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
];

const DEV_ADAPTERS = [
  chainId => ({
    contractName: "MockAdapter",
    target: {
      name: "cUSDC",
      guard: ethers.utils.parseEther("1"),
      series: DEV_SERIES_MATURITIES,
    },
    // deployments params MUST BE in order
    deploymentParams: {
      target: "0x0",
      oracle: ethers.constants.AddressZero, // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: "0x0",
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "4838400", // 4 weeks
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
      reward: "0x0",
    },
  }),
];
const DEV_FACTORIES = [
  chainId => ({
    contractName: "MockFactory",
    adapterContract: "MockAdapter",
    ifee: ethers.utils.parseEther("0.01"),
    stakeSize: ethers.utils.parseEther("1"),
    minm: "0", // 2 weeks
    maxm: "4838400", // 4 weeks
    mode: 1, // 0 monthly, 1 weekly;
    oracle: ethers.constants.AddressZero, // oracle address
    tilt: 0,
    targets: DEV_TARGETS,
  }),
];
// ------------------------------------

// -------------------------------------------------------
//  FOR MAINET SCENARIOS
// -------------------------------------------------------

// TODO(launch): fill in all below fields

// List of factories to deploy which includes a targets array to indicate,
// for factory, which target adapters to deploy
// (We are currently not deploying any factory)
const MAINNET_FACTORIES = [];

const CUSDC_WSTETH_SERIES_MATURITIES = [
  dayjs
    .utc()
    .week(dayjs().week() + 1)
    .startOf("week")
    .unix(),
];

// List of adapters to deploy directly (without factory)
const MAINNET_ADAPTERS = [
  chainId => ({
    contractName: "WstETHAdapter",
    target: {
      name: "wstETH",
      address: WSTETH_TOKEN.get(chainId),
      guard: ethers.utils.parseEther("1"),
      series: CUSDC_WSTETH_SERIES_MATURITIES,
    },
    // deployments params MUST BE in order
    deploymentParams: {
      oracle: MASTER_ORACLE_IMPL.get(chainId), // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: WETH_TOKEN.get(chainId),
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "604800", // 1 week
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
    },
  }),
  chainId => ({
    contractName: "CAdapter",
    // deployment params MUST BE in order
    target: {
      name: "cUSDC",
      address: CUSDC_TOKEN.get(chainId),
      guard: ethers.utils.parseEther("1"),
      series: CUSDC_WSTETH_SERIES_MATURITIES,
    },
    deploymentParams: {
      target: CUSDC_TOKEN.get(chainId),
      oracle: COMPOUND_PRICE_FEED.get(chainId), // oracle address
      ifee: ethers.utils.parseEther("0.01"),
      stake: WETH_TOKEN.get(chainId),
      stakeSize: ethers.utils.parseEther("0.01"),
      minm: "0", // 0 weeks
      maxm: "604800", // 1 week
      mode: 1, // 0 monthly, 1 weekly;
      tilt: 0,
      level: 31,
      reward: COMP_TOKEN.get(chainId),
    },
  }),
];
// ------------------------------------

global.dev = { FACTORIES: DEV_FACTORIES, ADAPTERS: DEV_ADAPTERS };
global.mainnet = { FACTORIES: MAINNET_FACTORIES, ADAPTERS: MAINNET_ADAPTERS };
