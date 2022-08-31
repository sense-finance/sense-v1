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
    contractName: "ERC4626Factory",
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
    factories: MAINNET_FACTORIES,
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString(), // 3 days
  },
  // goerli
  5: {
    divider: "0xa1514E3bA51C59d4E76956409143aE9734883Fd5",
    periphery: "0x03E98F3e15260C315eD60205a2708F9f37214776",
    factories: MAINNET_FACTORIES,
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString(), // 3 days
  },
};
