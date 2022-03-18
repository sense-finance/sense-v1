const {
  COMP_TOKEN,
  COMPOUND_PRICE_FEED,
  WETH_TOKEN,
  CUSDC_TOKEN,
  WSTETH_TOKEN,
  MASTER_ORACLE,
} = require("../../hardhat.addresses");
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

const C_USDC_MATURITIES = [
  dayjs("05/01/2022").utc().startOf("month").unix(),
  dayjs("07/01/2022").utc().startOf("month").unix(),
];

const C_FACTORY_TARGETS = [
  { name: "cUSDC", guard: ethers.utils.parseEther("100000"), series: C_USDC_MATURITIES, address: CUSDC_TOKEN.get("1") },
];

const MAINNET_FACTORIES = [
  {
    contractName: "CFactory",
    adapterContract: "CAdapter",
    ifee: ethers.utils.parseEther("0.0025"),
    stake: WETH_TOKEN.get("1"),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000", // 3 weeks
    maxm: "33507037", // 12 months
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE.get("1"),
    tilt: 0,
    targets: C_FACTORY_TARGETS,
    reward: COMP_TOKEN.get("1"),
  },
];

const WSTETH_MATURITIES = [
  dayjs("05/01/2022").utc().startOf("month").unix(),
  dayjs("07/01/2022").utc().startOf("month").unix(),
];

// List of adapters to deploy directly (without factory)
const MAINNET_ADAPTERS = [
  {
    contractName: "WstETHAdapter",
    target: {
      name: "wstETH",
      guard: ethers.utils.parseEther("40"),
      series: WSTETH_MATURITIES,
      address: WSTETH_TOKEN.get("1"),
    },
    deploymentParams: {
      oracle: MASTER_ORACLE.get("1"),
      ifee: ethers.utils.parseEther("0.0025"),
      stake: WETH_TOKEN.get("1"),
      stakeSize: ethers.utils.parseEther("0.25"),
      minm: "1814000", // 3 weeks
      maxm: "33507037", // 12 months
      mode: 0, // 0 monthly
      tilt: 0,
    },
  },
];

module.exports = {
  mainnet: {
    divider: "0x6961e8650A1548825f3e17335b7Db2158955C22f",
    periphery: "0xe983Ec9a2314a46F2713A838349bB05f3e629FE5",
    poolManager: "0xEBf829fB23bb3caf7eEeD89515264C18e2CE1dFb",
    vault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    spaceFactory: "0x6633c65e9f80c65d98abde3f9f4e6e504f4d5352",
    factories: MAINNET_FACTORIES,
    adapters: MAINNET_ADAPTERS,
  },
};
