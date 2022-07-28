const ethers = require("ethers");

const GOERLI_ADAPTERS = [
  {
    contractName: "MockAdapter",
    divider: "0xa1514E3bA51C59d4E76956409143aE9734883Fd5",
    target: "0x8872d8549Fe828f67132450B4a4a3c3E0689c942",
    ifee: ethers.utils.parseEther("0.0025"),
    adapterParams: {
      oracle: ethers.constants.AddressZero, // oracle address
      stake: "0xAEfcd438e64501D5a79a13d856DA5c4638EECC48",
      stakeSize: ethers.utils.parseEther("1"),
      minm: "0", // 2 weeks
      maxm: "4838400", // 4 weeks
      tilt: 0,
      level: 31,
      mode: 1, // 0 monthly, 1 weekly;
    },
    reward: "0x34AccF02eED08893697b9c212aDBF7a53FE173Fe" // airdrop
  }
]

module.exports = {
  goerli: {
    divider: "0xa1514E3bA51C59d4E76956409143aE9734883Fd5",
    periphery: "0x03E98F3e15260C315eD60205a2708F9f37214776",
    adapters: GOERLI_ADAPTERS
  },
};
