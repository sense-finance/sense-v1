const { WETH_TOKEN, MASTER_ORACLE, CDAI_TOKEN, COMP_TOKEN, CUSDC_TOKEN, CHAINS } = require("../../hardhat.addresses");
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

const SAMPLE_MATURITIES = [
  dayjs().utc().month(dayjs().utc().month() + 2).startOf("month").unix(),
  dayjs().utc().month(dayjs().utc().month() + 3).startOf("month").unix(),
];

// Only for hardhat, we will deploy adapters using Defender
const SAMPLE_TARGETS = [
  // { name: "cUSDT", series: [], address: CUSDT_TOKEN.get(CHAINS.MAINNET) }, // We can't deploy adapters whose target is not ERC20 compliant
  { name: "cUSDC", series: SAMPLE_MATURITIES, address: CUSDC_TOKEN.get(CHAINS.MAINNET) },
  { name: "cDAI", series: SAMPLE_MATURITIES, address: CDAI_TOKEN.get(CHAINS.MAINNET) },
];

const MAINNET_FACTORIES = [
  {
    contractName: "CFactory",
    adapterContract: "CAdapter",
    ifee: ethers.utils.parseEther("0.0010"),
    stake: WETH_TOKEN.get(CHAINS.MAINNET),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE.get(CHAINS.MAINNET),
    tilt: 0,
    guard: ethers.utils.parseEther("100000"), // $100'000
    targets: SAMPLE_TARGETS,
    reward: COMP_TOKEN.get(CHAINS.MAINNET)
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437", 
    factories: MAINNET_FACTORIES,
  },
  maturities: SAMPLE_MATURITIES,
};
