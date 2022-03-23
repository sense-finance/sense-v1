const { COMP_TOKEN, WETH_TOKEN, CUSDC_TOKEN, WSTETH_TOKEN, MASTER_ORACLE } = require("../../hardhat.addresses");
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
  // ~ 100,000 USDC guard
  { name: "cUSDC", guard: "500000000000000", series: C_USDC_MATURITIES, address: CUSDC_TOKEN.get("1") },
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
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xf22AC51fb2711B307be463db3d830a5B680E3dD1",
    poolManager: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    vault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    spaceFactory: "0x984682770f1EED90C00cd57B06b151EC12e7c51C",
    factories: MAINNET_FACTORIES,
    adapters: MAINNET_ADAPTERS,
  },
};
