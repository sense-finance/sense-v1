const { COMP_TOKEN, DAI_TOKEN, CDAI_TOKEN, COMPOUND_PRICE_FEED } = require("./hardhat.addresses");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const weekOfYear = require("dayjs/plugin/weekOfYear");
const ethers = require("ethers");

dayjs.extend(weekOfYear);
dayjs.extend(utc);

// For dev scenarios ------------
const DEV_SERIES_MATURITIES = [
  // beginning of the week falling between 0 and 1 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 1)
    .startOf("week")
    .add(1, "day")
    .unix(),
  // beginning of the week falling between 1 and 2 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 2)
    .startOf("week")
    .add(1, "day")
    .unix(),
];
const DEV_TARGETS = [
  { name: "cDAI", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cETH", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cUSDT", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "cUSDC", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "f6-DAI", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES },
  { name: "f8-DAI", guard: ethers.constants.MaxUint256, series: DEV_SERIES_MATURITIES }
];

const DEV_FACTORIES = [(chainId) => ({
  contractName: "MockFactory",
  adapterContract: "MockAdapter",
  ifee: ethers.utils.parseEther("0.01"),
  stakeSize: ethers.utils.parseEther("1"),
  minm: "0", // 2 weeks
  maxm: "4838400", // 4 weeks
  mode: 1, // 0 monthly, 1 weekly;
  oracle: COMPOUND_PRICE_FEED.get(chainId), // oracle address
  tilt: 0,
  targets: DEV_TARGETS
})]
// ------------------------------------

// For mainnet scenarios (TBD BEFORE DEPLOYING!!) ------------
const MAINNET_SERIES_MATURITIES = [
  // beginning of the week falling between 2 and 3 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 3)
    .startOf("week")
    .add(1, "day")
    .unix(),
  // beginning of the week falling between 3 and 4 weeks from now
  dayjs
    .utc()
    .week(dayjs().week() + 4)
    .startOf("week")
    .add(1, "day")
    .unix(),
];
const MAINNET_TARGETS = (chainId) => [{ name: "cDAI", address: CDAI_TOKEN.get(chainId), guard: ethers.constants.MaxUint256, series: MAINNET_SERIES_MATURITIES }];

const MAINNET_FACTORIES = [(chainId) => ({
  contractName: "CFactory",
  adapterContract: "CAdapter",
  reward: COMP_TOKEN.get(chainId),
  ifee: ethers.utils.parseEther("0.01"),
  stake: DAI_TOKEN.get(chainId),
  stakeSize: ethers.utils.parseEther("1"),
  minm: "1209600", // 2 weeks
  maxm: "8467200", // 14 weeks
  mode: 1, // 0 monthly, 1 weekly;
  oracle: COMPOUND_PRICE_FEED.get(chainId), // oracle address
  tilt: 0,
  targets: MAINNET_TARGETS(chainId),
})]
// ------------------------------------

global.dev = { FACTORIES: DEV_FACTORIES, ADAPTERS: {} };
global.mainnet = { FACTORIES: MAINNET_FACTORIES, ADAPTERS: {}};

