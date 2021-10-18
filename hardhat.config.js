require("dotenv/config");
require("@nomiclabs/hardhat-etherscan");
// require("@tenderly/hardhat-tenderly");
require("hardhat-abi-exporter");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-spdx-license-identifier");
require("hardhat-watcher");
// import "./tasks";

const accounts = {
  mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
};

const config = {
  defaultNetwork: "hardhat",
  // etherscan: {
  //   apiKey: process.env.ETHERSCAN_API_KEY,
  // },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dev: {
      default: 1,
      // dev address mainnet
      // 1: "",
    },
  },
  networks: {
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      accounts,
      gasPrice: 120 * 1000000000, // 12 GWei
      chainId: 1,
    },
    hardhat: {
      forking: {
        enabled: true,
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      },
      chainId: 111,
      gas: 12000000,
      blockGasLimit: 21000000,
      // FIXME: we shouldn't need to do this, is the divider really too big?
      allowUnlimitedContractSize: true,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts,
      chainId: 42161,
      live: true,
      saveDeployments: true,
      blockGasLimit: 700000,
    },
  },
  paths: {
    sources: "src",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
    ],
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  //   tenderly: {
  //     project: process.env.TENDERLY_PROJECT,
  //     username: process.env.TENDERLY_USERNAME,
  //   },
  watcher: {
    compile: {
      tasks: ["compile"],
      files: ["./src"],
      verbose: true,
    },
  },
};

module.exports = config;
