const { CHAINS } = require("./hardhat.addresses");
const fs = require("fs");
require("dotenv/config");
require("@nomiclabs/hardhat-etherscan");
require("@tenderly/hardhat-tenderly");
require("hardhat-contract-sizer");
require("hardhat-abi-exporter");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-spdx-license-identifier");
require("hardhat-watcher");
require("hardhat-preprocessor");
require("./cli");
require("./hardhat.seed");

const accounts = {
  mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
  // For the hardhat test network
  accountsBalance: "10000000000000000000000000",
};

const getRemappings = () => {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean) // remove empty lines
    .map(line => line.trim().split("="));
};

exports.getRemappings = getRemappings;

module.exports = {
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
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
    goerli_fork: {
      url: `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      accounts,
      chainId: 5,
      saveDeployments: false,
      forking: {
        enabled: true,
        url: `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      },
    },
    hardhat: {
      mining: {
        auto: true,
      },
      accounts,
      saveDeployments: false,
      forking: {
        enabled: true,
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
      },
      chainId: parseInt(process.env.CHAIN_ID || CHAINS.HARDHAT),
      // gas: 12000000,
      // saveDeployments: false,
      // blockGasLimit: 21000000,
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
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: process.env.SIM === "true" ? 100 : 100,
          },
        },
      },
      {
        version: "0.7.5",
        settings: {
          optimizer: {
            enabled: true,
            // The Balancer Vault becomes too large to deploy with more optimizer runs,
            // but we only need to deploy it on sim runs (we use the existing mainnet Vault on prod runs)
            runs: process.env.SIM === "true" ? 100 : 100,
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
  tenderly: {
    project: process.env.TENDERLY_PROJECT,
    username: process.env.TENDERLY_USERNAME,
  },
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
  preprocess: {
    eachLine: () => ({
      transform: line => {
        if (line.match(/^\s*import /i)) {
          for (const [from, to] of getRemappings()) {
            // remappings for yield-daddy's contracts
            if (line.includes(from) && line.includes("yield-daddy")) {
              line = line.replace(from, to);
              // workaround: some remappings end up with /sr/src so we fix it this way
              line = line.replace("src/src", "src");
              continue;
            }
            // remappings for morpho's contracts using @rari-capital/solmate
            if (from === "@rari-capital/solmate" && line.includes("@rari-capital")) {
              line = line.replace(from, to);
              continue;
            }
            // remappings for sense's contracts using solmate
            if (from === "solmate/" && !line.includes("solmate/src") && !line.includes("@rari-capital")) {
              line = line.replace(from, to);
              continue;
            }
            line = line.replace(from, to);
            line = line.replace("src/src", "src"); // workaround
          }
        }
        return line;
      },
    }),
  },
};
