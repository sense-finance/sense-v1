require("dotenv/config");
require("@nomiclabs/hardhat-etherscan");
// require("@tenderly/hardhat-tenderly");
require("hardhat-contract-sizer");
require("hardhat-abi-exporter");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-spdx-license-identifier");
require("hardhat-watcher");
require("./cli");
require("./hardhat.seed");

const accounts = {
  mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
  // for the hardhat test network
  accountsBalance: "10000000000000000000000000",
};

module.exports = {
  defaultNetwork: "hardhat",
  // etherscan: {
  //   apiKey: process.env.ETHERSCAN_API_KEY,
  // },
  namedAccounts: {
    deployer: {
      default: parseInt(process.env.DEPLOYER_INDEX || 0),
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
      gasPrice: "auto",
      gasMultiplier: 1.2,
      chainId: 1,
      saveDeployments: true,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      accounts,
      gasPrice: 120 * 1000000000, // 120 GWei
      chainId: 42,
      saveDeployments: true,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      accounts,
      chainId: 5,
      saveDeployments: true,
    },
    hardhat: {
      mining: {
        auto: true,
      },
      accounts,
      forking: {
        enabled: true,
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      },
      chainId: process.env.CHAIN_ID !== undefined ? parseInt(process.env.CHAIN_ID) : 111,
      gas: 12000000,
      saveDeployments: false,
      blockGasLimit: 21000000,
      // blockNumber: 13491969,
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
    sources: "src/",
    deployments: "deployments",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.11",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
      {
        version: "0.7.5",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
    ],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: true,
    strict: true,
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
    test: {
      tasks: [{ command: "test", params: { testFiles: ["{path}"] } }],
      files: ["./test/**/*"],
      verbose: true,
    },
  },
};
