const { WETH_TOKEN, CHAINS, IMUSD_TOKEN } = require("../../hardhat.addresses");
const ethers = require("ethers");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

// Only for hardhat, we will deploy adapters using Defender
const SAMPLE_MATURITIES = [
  dayjs()
    .utc()
    .month(dayjs().utc().month() + 3)
    .startOf("month")
    .unix(),
  dayjs()
    .utc()
    .month(dayjs().utc().month() + 4)
    .startOf("month")
    .unix(),
];
const SAMPLE_TARGETS = [
  { name: "mUSD", series: SAMPLE_MATURITIES, address: IMUSD_TOKEN.get(CHAINS.MAINNET) },
];

const MAINNET_FACTORIES = [
  {
    contractName: "ERC4626CropsFactory",
    ifee: ethers.utils.parseEther("0.0010"), // 0.1%
    stake: WETH_TOKEN.get(CHAINS.MAINNET),
    stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
    minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 0, // 0 = monthly
    tilt: 0,
    guard: ethers.utils.parseEther("100000"), // $100'000
    targets: SAMPLE_TARGETS,
  },
];

module.exports = {
  // mainnet
  1: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437",
    erc4626Factory: "0x1b037B8aC231A13a22eD91e96228cF3a2259e25B",
    oracle: "0x11D341d35BF95654BC7A9db59DBc557cCB4ea101",
    factories: MAINNET_FACTORIES,
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString(), // 3 days
  },
};
