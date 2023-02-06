const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  DIVIDER_1_2_0,
  SENSE_MASTER_ORACLE,
  NON_CROP_4626_FACTORY,
  sanFRAX_EUR_Wrapper,
  sanFRAX_EUR_Wrapper_ADAPTER,
  ANGLE,
} = require("../../hardhat.addresses");
const ethers = require("ethers");

const MAINNET_CONTRACTS = [
  // {
  //   contractName: "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626Factory.sol:ERC4626Factory",
  //   address: NON_CROP_4626_FACTORY.get(CHAINS.MAINNET),
  //   args: [
  //     DIVIDER_1_2_0.get(CHAINS.MAINNET),
  //     SENSE_MULTISIG.get(CHAINS.MAINNET),
  //     SENSE_MULTISIG.get(CHAINS.MAINNET),
  //     [
  //       SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
  //       WETH_TOKEN.get(CHAINS.MAINNET),
  //       ethers.utils.parseEther("0.25"), // 0.25 WETH
  //       ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
  //       (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
  //       ethers.utils.parseEther("0.001"), // 0.001%
  //       0, // 0 = monthly
  //       0,
  //       31,
  //     ],
  //   ],
  // },
  {
    contractName:
      "@sense-finance/v1-core/src/adapters/abstract/erc4626/OwnableERC4626CropAdapter.sol:OwnableERC4626CropAdapter",
    address: sanFRAX_EUR_Wrapper_ADAPTER.get(CHAINS.MAINNET),
    args: [
      DIVIDER_1_2_0.get(CHAINS.MAINNET),
      sanFRAX_EUR_Wrapper.get(CHAINS.MAINNET),
      SENSE_MULTISIG.get(CHAINS.MAINNET),
      5e15,
      [
        SENSE_MASTER_ORACLE.get(CHAINS.MAINNET),
        WETH_TOKEN.get(CHAINS.MAINNET),
        ethers.utils.parseEther("0.25"), // 0.25 WETH
        ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
        (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
        0,
        31,
        0, // 0 = monthly
      ],
      ANGLE.get(CHAINS.HARDHAT),
    ],
  },
];

const GOERLI_CONTRACTS = [
  {
    contractName: "@sense-finance/v1-core/src/adapters/abstract/factories/ERC4626Factory.sol:ERC4626Factory",
    address: NON_CROP_4626_FACTORY.get(CHAINS.GOERLI),
    args: [
      DIVIDER_1_2_0.get(CHAINS.GOERLI),
      SENSE_MULTISIG.get(CHAINS.GOERLI),
      SENSE_MULTISIG.get(CHAINS.GOERLI),
      [
        SENSE_MASTER_ORACLE.get(CHAINS.GOERLI),
        WETH_TOKEN.get(CHAINS.GOERLI),
        ethers.utils.parseEther("0.25"), // 0.25 WETH
        ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
        (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
        ethers.utils.parseEther("0.001"), // 0.001%
        0, // 0 = monthly
        0,
        31,
      ],
    ],
  },
];

module.exports = {
  // mainnet
  1: { contracts: MAINNET_CONTRACTS },
  5: { contracts: GOERLI_CONTRACTS },
};
