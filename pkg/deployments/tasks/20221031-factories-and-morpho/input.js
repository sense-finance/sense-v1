const { WETH_TOKEN, CHAINS, SENSE_MULTISIG, MORPHO_USDC, MORPHO_DAI } = require("../../hardhat.addresses");
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
  { name: "maDAI", series: SAMPLE_MATURITIES, address: MORPHO_DAI.get(CHAINS.MAINNET) },
  { name: "maUSDC", series: SAMPLE_MATURITIES, address: MORPHO_USDC.get(CHAINS.MAINNET) },
  // { name: "maUSDT", series: SAMPLE_MATURITIES, address: MORPHO_USDT.get(CHAINS.MAINNET) },
];

const MAINNET_FACTORIES = [
  // {
  //   contractName: "ERC4626CropsFactory",
  //   ifee: ethers.utils.parseEther("0.0010"), // 0.1%
  //   stake: WETH_TOKEN.get(CHAINS.MAINNET),
  //   stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  //   minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  //   maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  //   mode: 0, // 0 = monthly
  //   tilt: 0,
  //   guard: ethers.utils.parseEther("100000"), // $100'000
  //   targets: SAMPLE_TARGETS,
  // },
  // {
  //   contractName: "ERC4626CropFactory",
  //   ifee: ethers.utils.parseEther("0.0010"), // 0.1%
  //   stake: WETH_TOKEN.get(CHAINS.MAINNET),
  //   stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  //   minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  //   maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  //   mode: 0, // 0 = monthly
  //   tilt: 0,
  //   guard: ethers.utils.parseEther("100000"), // $100'000
  //   targets: SAMPLE_TARGETS,
  // },
  {
    // Since there's a contract from yield daddy library called ERC4626Factory, we need to use this format to specify specifically which contract we are referring to
    contract: "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626Factory.sol:ERC4626Factory",
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

const GOERLI_FACTORIES = [
  {
    contract: "MockFactory",
    contractName: "MockFactory",
    ifee: ethers.utils.parseEther("0.0010"), // 0.1%
    stake: WETH_TOKEN.get(CHAINS.GOERLI),
    stakeSize: ethers.utils.parseEther("0.05"), // 0.05 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 1, // 0 = weekly
    tilt: 0,
    guard: ethers.utils.parseEther("100000"), // $100'000 (not used in Goerli)
    targets: [],
  },
];

module.exports = {
  // mainnet
  1: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437",
    oracle: "0x11D341d35BF95654BC7A9db59DBc557cCB4ea101",
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    factories: MAINNET_FACTORIES,
  },
  5: {
    divider: "0x09B10E45A912BcD4E80a8A3119f0cfCcad1e1f12",
    periphery: "0x4bCBA1316C95B812cC014CA18C08971Ce1C10861",
    oracle: "0xB3e70779c1d1f2637483A02f1446b211fe4183Fa",
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    factories: GOERLI_FACTORIES,
  },
};
