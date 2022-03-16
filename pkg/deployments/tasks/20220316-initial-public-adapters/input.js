const {
  COMP_TOKEN,
  COMPOUND_PRICE_FEED,
  WETH_TOKEN,
  CUSDC_TOKEN,
  WSTETH_TOKEN,
  MASTER_ORACLE_IMPL,
} = require("../hardhat.addresses");
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

const C_USDC_MATURITIES = [];

const C_FACTORY_TARGETS = [{ name: "cUSDC", guard: ethers.utils.parseEther("250000"), series: C_USDC_MATURITIES }];

const MAINNET_FACTORIES = [
  chainId => ({
    contractName: "CFactory",
    adapterContract: "cAdapter",
    ifee: ethers.utils.parseEther("0.0025"),
    stake: WETH_TOKEN.get(chainId),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000", // 3 weeks
    maxm: "33507037", // 12 months, 3 weeks
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE_IMPL.get(chainId),
    tilt: 0,
    targets: C_FACTORY_TARGETS,
  }),
];

const WSTETH_MATURITIES = [
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
      guard: ethers.utils.parseEther("100"),
      series: WSTETH_MATURITIES,
    },
    deploymentParams: {
      oracle: MASTER_ORACLE_IMPL.get(chainId),
      ifee: ethers.utils.parseEther("0.0025"),
      stake: WETH_TOKEN.get(chainId),
      stakeSize: ethers.utils.parseEther("0.25"),
      minm: "1814000", // 3 weeks
      maxm: "33507037", // 12 months, 3 weeks
      mode: 0, // 0 monthly
      tilt: 0,
    },
  }),
];

global.mainnet = { FACTORIES: MAINNET_FACTORIES, ADAPTERS: MAINNET_ADAPTERS };

module.exports = {
  mainnet: {
    divider: "0x6961e8650A1548825f3e17335b7Db2158955C22f",
    periphery: "0xe983Ec9a2314a46F2713A838349bB05f3e629FE5",
  },
};
