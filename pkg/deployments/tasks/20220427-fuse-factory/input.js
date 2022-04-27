const { WETH_TOKEN, MASTER_ORACLE, F18DAI_TOKEN } = require("../../hardhat.addresses");
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

// Series will NOT be sponsored on mainnet (this will be done via Defender)
const F18DAI_MATURITIES = [
  dayjs("06/01/2022").utc().startOf("month").unix(),
  dayjs("08/01/2022").utc().startOf("month").unix(),
];

const F_FACTORY_TARGETS = [
  // ~ 100,000 USDC guard
  { name: "f18DAI", guard: "500000000000000", series: F18DAI_MATURITIES, address: F18DAI_TOKEN.get("1") },
];

const MAINNET_FACTORIES = [
  {
    contractName: "FFactory",
    adapterContract: "FAdapter",
    ifee: ethers.utils.parseEther("0.0025"),
    stake: WETH_TOKEN.get("1"),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000", // 3 weeks
    maxm: "33507037", // 12 months
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE.get("1"),
    tilt: 0,
    targets: F_FACTORY_TARGETS // TODO: define if we want to deploy adapters and sponsor series
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "", // TODO: add new periphery 
    poolManager: "0xf01eb98de53ed964AC3F786b80ED8ce33f05F417",
    vault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    spaceFactory: "0x984682770f1EED90C00cd57B06b151EC12e7c51C",
    factories: MAINNET_FACTORIES,
    adapters: [],
  },
};
