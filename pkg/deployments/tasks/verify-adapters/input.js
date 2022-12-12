const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  MORPHO_USDC,
  DIVIDER_1_2_0,
  OWNABLE_MAUSDC_ADAPTER,
  WSTETH_OWNABLE_ADAPTER,
  OWNABLE_MAUSDT_ADAPTER,
  MORPHO_USDT,
  SENSE_MASTER_ORACLE,
  CUSDC_OWNABLE_ADAPTER,
  CUSDC_TOKEN,
} = require("../../hardhat.addresses");
const ethers = require("ethers");

const MAINNET_ADAPTERS = [
  {
    contractName:
      "@sense-finance/v1-core/src/adapters/implementations/lido/OwnableWstETHAdapter.sol:OwnableWstETHAdapter",
    address: WSTETH_OWNABLE_ADAPTER.get(CHAINS.MAINNET),
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    target: MORPHO_USDC.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    ifee: ethers.utils.parseEther("0"), // 0%, no issuance fees
    adapterParams: {
      oracle: ethers.constants.AddressZero,
      stake: WETH_TOKEN.get(CHAINS.MAINNET),
      stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
      minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
      maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
      tilt: 0,
      level: 31,
      mode: 0, // 0 = monthly
    },
  },
  {
    contractName:
      "@sense-finance/v1-core/src/adapters/abstract/erc4626/OwnableERC4626Adapter.sol:OwnableERC4626Adapter",
    address: OWNABLE_MAUSDC_ADAPTER.get(CHAINS.MAINNET),
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    target: MORPHO_USDC.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    ifee: ethers.utils.parseEther("0.0005"), // 0.05%
    adapterParams: {
      oracle: SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
      stake: WETH_TOKEN.get(CHAINS.MAINNET),
      stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
      minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
      maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
      tilt: 0,
      level: 31,
      mode: 0, // 0 = monthly
    },
  },
  {
    contractName:
      "@sense-finance/v1-core/src/adapters/abstract/erc4626/OwnableERC4626Adapter.sol:OwnableERC4626Adapter",
    address: OWNABLE_MAUSDT_ADAPTER.get(CHAINS.MAINNET),
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    target: MORPHO_USDT.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    ifee: ethers.utils.parseEther("0.0005"), // 0.05%
    adapterParams: {
      oracle: SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
      stake: WETH_TOKEN.get(CHAINS.MAINNET),
      stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
      minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
      maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
      tilt: 0,
      level: 31,
      mode: 0, // 0 = monthly
    },
  },
];

const GOERLI_ADAPTERS = [
  {
    contractName: "MockOwnableAdapter",
    address: CUSDC_OWNABLE_ADAPTER.get(CHAINS.GOERLI),
    divider: DIVIDER_1_2_0.get(CHAINS.GOERLI),
    target: CUSDC_TOKEN.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    ifee: ethers.utils.parseEther("0.0005"), // 0.05%
    adapterParams: {
      oracle: SENSE_MASTER_ORACLE.get(CHAINS.GOERLI),
      stake: WETH_TOKEN.get(CHAINS.GOERLI),
      stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
      minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
      maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
      tilt: 0,
      level: 31,
      mode: 0, // 0 = monthly
    },
  },
];

module.exports = {
  // mainnet
  1: { adapters: MAINNET_ADAPTERS },
  5: { adapters: GOERLI_ADAPTERS },
};
