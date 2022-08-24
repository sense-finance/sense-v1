const { WETH_TOKEN, WSTETH_TOKEN, CHAINS } = require("../../hardhat.addresses");
const ethers = require("ethers");

// List of adapters to deploy directly (without factory)
const MAINNET_ADAPTERS = [
  {
    contractName: "WstETHAdapter",
    target: {
      name: "wstETH",
      guard: ethers.utils.parseEther("100"),
      series: [],
      address: WSTETH_TOKEN.get(CHAINS.MAINNET),
    },
    deploymentParams: {
      divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
      target: WSTETH_TOKEN.get(CHAINS.MAINNET),
      ifee: ethers.utils.parseEther("0"),
      adapterParams: {
        oracle: ethers.constants.AddressZero,
        stake: WETH_TOKEN.get(CHAINS.MAINNET),
        stakeSize: ethers.utils.parseEther("0.25"),
        minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
        maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
        tilt: 0,
        level: 31,
        mode: 0, // 0 monthly
      },
    },
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437",
    adapters: MAINNET_ADAPTERS,
  },
};
