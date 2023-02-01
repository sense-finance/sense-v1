const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  SENSE_MASTER_ORACLE,
  DIVIDER_1_2_0,
  PERIPHERY_1_4_0,
  sanFRAX_EUR_Wrapper,
  RLV_FACTORY,
  ANGLE,
} = require("../../hardhat.addresses");
const ethers = require("ethers");

const MAINNET_FACTORY = {
  contract:
    "@sense-finance/v1-core/src/adapters/abstract/factories/OwnableERC4626CropFactory.sol:OwnableERC4626CropFactory",
  contractName: "OwnableERC4626CropFactory",
  ifee: ethers.utils.parseEther("0.005"), // 0.005%
  stake: WETH_TOKEN.get(CHAINS.MAINNET),
  stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  mode: 0, // 0 = monthly
  tilt: 0,
  guard: ethers.utils.parseEther("100000"), // $100'000
  target: { name: "sanFRAX_EUR_Wrapper", address: sanFRAX_EUR_Wrapper.get(CHAINS.MAINNET) },
};
const GOERLI_FACTORY = {
  contract:
    "@sense-finance/v1-core/src/adapters/abstract/factories/OwnableERC4626CropFactory.sol:OwnableERC4626CropFactory",
  contractName: "OwnableERC4626CropFactory",
  ifee: ethers.utils.parseEther("0.005"), // 0.005%
  stake: WETH_TOKEN.get(CHAINS.MAINNET),
  stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
  minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  mode: 0, // 0 = monthly
  tilt: 0,
  guard: ethers.utils.parseEther("100000"), // $100'000
  target: { name: "sanFRAX_EUR_Wrapper", address: sanFRAX_EUR_Wrapper.get(CHAINS.GOERLI) },
};
module.exports = {
  // mainnet
  1: {
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    periphery: PERIPHERY_1_4_0.get(CHAINS.MAINNET),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    factoryArgs: MAINNET_FACTORY,
    rlvFactory: RLV_FACTORY.get(CHAINS.MAINNET),
    reward: ANGLE.get(CHAINS.MAINNET),
  },
  5: {
    divider: DIVIDER_1_2_0.get(CHAINS.GOERLI),
    periphery: PERIPHERY_1_4_0.get(CHAINS.GOERLI),
    oracle: SENSE_MASTER_ORACLE.get(CHAINS.GOERLI),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    factoryArgs: GOERLI_FACTORY,
    rlvFactory: RLV_FACTORY.get(CHAINS.GOERLI),
    reward: ANGLE.get(CHAINS.GOERLI),
  },
};
