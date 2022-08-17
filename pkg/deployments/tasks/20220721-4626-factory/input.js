const { WETH_TOKEN, CHAINS } = require("../../hardhat.addresses");
const ethers = require("ethers");

const MAINNET_FACTORIES = [
  {
    contractName: "ERC4626Factory",
    ifee: ethers.utils.parseEther("0.0025"),
    stake: WETH_TOKEN.get(CHAINS.MAINNET),
    stakeSize: ethers.utils.parseEther("0.25"),
    minm: ((365.25 * 24 * 60 * 60) / 12).toString(), // 1 month
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 0, // 0 = monthly
    tilt: 0
  },
];

module.exports = {
  // mainnet
  1: {
    divider: "0x86bA3E96Be68563E41c2f5769F1AF9fAf758e6E0",
    periphery: "0xFff11417a58781D3C72083CB45EF54d79Cd02437", 
    factories: MAINNET_FACTORIES,
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString() // 3 days
  },
  // goerli
  5: {
    divider: "0xa1514E3bA51C59d4E76956409143aE9734883Fd5",
    periphery: "0x03E98F3e15260C315eD60205a2708F9f37214776", 
    factories: MAINNET_FACTORIES,
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString() // 3 days
  },
};
