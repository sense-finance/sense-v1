const { WETH_TOKEN, WSTETH_TOKEN, MASTER_ORACLE } = require("../../hardhat.addresses");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");
const ethers = require("ethers");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

// List of adapters to deploy directly (without factory)
const MAINNET_ADAPTERS = [
  {
    contractName: "WstETHAdapter",
    target: {
      name: "wstETH",
      guard: ethers.utils.parseEther("40"),
      series: [],
      address: WSTETH_TOKEN.get("1"),
    },
    deploymentParams: {
      divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
      target: WSTETH_TOKEN.get("1"), 
      underlying: WETH_TOKEN.get("1"), 
      ifee: ethers.utils.parseEther("0"),
      adapterParams: {
        oracle: MASTER_ORACLE.get("1"),
        stake: WETH_TOKEN.get("1"),
        stakeSize: ethers.utils.parseEther("0"),
        minm: "2629746", // 1 month
        maxm: "315569520", // 10 years
        tilt: 0, 
        level: 31,
        mode: 0, // 0 monthly
      }
    },
  },
];

module.exports = {
  mainnet: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437",
    poolManager: "0xf01eb98de53ed964ac3f786b80ed8ce33f05f417",
    vault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
    spaceFactory: "0x984682770f1EED90C00cd57B06b151EC12e7c51C",
    adapters: MAINNET_ADAPTERS,
  },
};
