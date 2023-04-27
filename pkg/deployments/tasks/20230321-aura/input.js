const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  SENSE_MASTER_ORACLE,
  DIVIDER_1_2_0,
  PERIPHERY_1_4_0,
  RLV_FACTORY,
  BAL,
  AURA,
} = require("../../hardhat.addresses");
const ethers = require("ethers");
const { percentageToDecimal } = require("../../hardhat.utils");

const MAINNET_ADAPTER = {
  contract:
    "@sense-finance/v1-core/src/adapters/implementations/aura/OwnableAuraAdapter.sol:OwnableAuraAdapter",
  contractName: "OwnableAuraAdapter",
  ifee: ethers.utils.parseEther(percentageToDecimal(0.05).toString()), // 0.05%
  stake: WETH_TOKEN.get(CHAINS.MAINNET),
  stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  mode: 0, // 0 = monthly
  tilt: 0,
  level: 31,
  guard: ethers.utils.parseEther("100000"), // $100'000
  rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
  rewardTokens: [AURA.get(CHAINS.MAINNET), BAL.get(CHAINS.MAINNET)],
};

const GOERLI_ADAPTER = {
  contract:
    "@sense-finance/v1-core/src/adapters/implementations/aura/OwnableAuraAdapter.sol:OwnableAuraAdapter",
  contractName: "OwnableAuraAdapter",
  ifee: ethers.utils.parseEther(percentageToDecimal(0.05).toString()), // 0.05%
  stake: WETH_TOKEN.get(CHAINS.MAINNET),
  stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  mode: 0, // 0 = monthly
  tilt: 0,
  level: 31,
  guard: ethers.utils.parseEther("100000"), // $100'000
  rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
  rewardTokens: [],
};

module.exports = {
  // mainnet
  1: {
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    periphery: PERIPHERY_1_4_0.get(CHAINS.MAINNET),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    adapterArgs: MAINNET_ADAPTER,
    rlvFactory: RLV_FACTORY.get(CHAINS.MAINNET),
  },
  5: {
    divider: DIVIDER_1_2_0.get(CHAINS.GOERLI),
    periphery: PERIPHERY_1_4_0.get(CHAINS.GOERLI),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.GOERLI),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    adapterArgs: GOERLI_ADAPTER,
    rlvFactory: RLV_FACTORY.get(CHAINS.GOERLI),
  },
};
