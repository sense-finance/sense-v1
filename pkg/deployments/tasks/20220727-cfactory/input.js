const { WETH_TOKEN, MASTER_ORACLE, CDAI_TOKEN, COMP_TOKEN, CUSDT_TOKEN } = require("../../hardhat.addresses");
const ethers = require("ethers");

// Only for hardhat, we will deploy adapters using Defender
const C_FACTORY_TARGETS = [
  // { name: "cUSDT", series: [], address: CUSDT_TOKEN.get("1") }, // We can't deploy adapters whose target is not ERC20 compliant
  { name: "cDAI", series: [], address: CDAI_TOKEN.get("1") },
];

const MAINNET_FACTORIES = [
  {
    contractName: "CFactory",
    adapterContract: "CAdapter",
    ifee: ethers.utils.parseEther("0.0010"),
    stake: WETH_TOKEN.get("1"),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 0, // 0 monthly
    oracle: MASTER_ORACLE.get("1"),
    tilt: 0,
    targets: C_FACTORY_TARGETS,
    reward: COMP_TOKEN.get("1")
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437", 
    factories: MAINNET_FACTORIES
  },
};
