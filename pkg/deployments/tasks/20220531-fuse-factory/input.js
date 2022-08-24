const {
  WETH_TOKEN,
  MASTER_ORACLE,
  F18DAI_TOKEN,
  OLYMPUS_POOL_PARTY,
  CHAINS,
} = require("../../hardhat.addresses");
const ethers = require("ethers");

// TODO: decide which adapter targets to deploy
const F_FACTORY_TARGETS = [
  {
    name: "f18DAI",
    series: [],
    address: F18DAI_TOKEN.get(CHAINS.MAINNET),
    comptroller: OLYMPUS_POOL_PARTY.get(CHAINS.MAINNET),
  },
];

const MAINNET_FACTORIES = [
  {
    contractName: "FFactory",
    adapterContract: "FAdapter",
    ifee: ethers.utils.parseEther("0.0025"),
    stake: WETH_TOKEN.get(CHAINS.MAINNET),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: "1814000", // 3 weeks
    maxm: "33507037", // 12 months
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE.get(CHAINS.MAINNET),
    tilt: 0,
    targets: F_FACTORY_TARGETS,
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437",
    factories: MAINNET_FACTORIES,
  },
};
