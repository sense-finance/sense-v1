const poolDirectoryAbi = require("./abi/poolDirectory.json");

const FUSE_ADDRESSES = new Map();
// Mainnet fork
FUSE_ADDRESSES.set(
  "111",
  new Map([
    ["poolDirectory", "0x835482FE0532f169024d5E9410199369aAD5C77E"],
    ["poolLens", "0x8dA38681826f4ABBe089643D2B3fE4C6e4730493"],
    ["safeLiquidator", "0xf0f3a1494ae00b5350535b7777abb2f499fc13d4"],
    ["feeDistributor", "0xa731585ab05fC9f83555cf9Bff8F58ee94e18F85"],
    ["comptrollerImplementation", "0xe16db319d9da7ce40b666dd2e365a4b8b3c18217"],
  ]),
);

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const chainId = await getChainId();
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const deployerSigner = await ethers.getSigner(deployer);

  //   console.log("Deploy a cFeed implementation");
  //   const { address: cFeedAddress } = await deploy("CFeed", {
  //     from: deployer,
  //     args: [],
  //     log: true,
  //   });

  if (!FUSE_ADDRESSES.has(chainId)) throw Error("Addresses not found");
  const fuseAddresses = FUSE_ADDRESSES.get(chainId);

  const poolDirectory = new ethers.Contract(fuseAddresses.get("poolDirectory"), poolDirectoryAbi, deployerSigner);

  const name = "Sense Pool";
  const implementation = fuseAddresses.get("comptrollerImplementation");
  const enforceWhitelist = false;
  const closeFactor = ethers.utils.parseEther("0.051");
  const liquidationIncentive = ethers.utils.parseEther("1");
  const chainlinkOracleV2 = "0xb0602af43Ca042550ca9DA3c33bA3aC375d20Df4";

  await poolDirectory
    .deployPool(name, implementation, enforceWhitelist, closeFactor, liquidationIncentive, chainlinkOracleV2)
    .then(tx => tx.wait());

  const [, pools] = await poolDirectory.getPoolsByAccount(deployer);
  const [pool] = pools;
  console.log(pools);
};

module.exports.tags = ["PoolManager"];
module.exports.dependencies = [];
