const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  SENSE_MASTER_ORACLE,
  DIVIDER_1_2_0,
  PERIPHERY_1_4_0,
  BB_wstETH4626,
} = require("../../hardhat.addresses");
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
  { name: "BB_wstETH4626", series: SAMPLE_MATURITIES, address: BB_wstETH4626.get(CHAINS.MAINNET) },
];

const MAINNET_FACTORIES = [
  {
    // Since there's a contract from yield daddy library called ERC4626Factory, we need to use this format to specify specifically which contract we are referring to
    contract: "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626Factory.sol:ERC4626Factory",
    contractName: "ERC4626Factory",
    ifee: ethers.utils.parseEther("0.0010"), // 0.001%
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
    targets: [],
  },
];

module.exports = {
  // mainnet
  1: {
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    periphery: PERIPHERY_1_4_0.get(CHAINS.MAINNET),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    factories: MAINNET_FACTORIES,
  },
  5: {
    divider: DIVIDER_1_2_0.get(CHAINS.GOERLI),
    periphery: PERIPHERY_1_4_0.get(CHAINS.GOERLI),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.GOERLI),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    factories: GOERLI_FACTORIES,
  },
};
