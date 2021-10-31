const UNI_FACTORY = new Map();
// Mainnet
UNI_FACTORY.set("1", "0x1F98431c8aD98523631AE4a59f267346ea31F984");
// Local Mainnet fork
UNI_FACTORY.set("111", "0x1F98431c8aD98523631AE4a59f267346ea31F984");
// TODO: Arbitrum

const UNI_ROUTER = new Map();
// Mainnet
UNI_ROUTER.set("1", "0xE592427A0AEce92De3Edee1F18E0157C05861564");
// Local Mainnet fork
UNI_ROUTER.set("111", "0xE592427A0AEce92De3Edee1F18E0157C05861564");
// TODO: Arbitrum

const CDAI = new Map();
// Mainnet
CDAI.set("1", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");
// Local Mainnet fork
CDAI.set("111", "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643");
// TODO: Arbitrum

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  // const { deploy } = deployments;
  // const { deployer } = await getNamedAccounts();
  // const chainId = await getChainId();
  // const divider = await ethers.getContract("Divider");
  // if (!UNI_FACTORY.has(chainId)) throw Error("No uni factory address found");
  // if (!UNI_ROUTER.has(chainId)) throw Error("No uni router address found");
  // const uniFactory = UNI_FACTORY.get(chainId);
  // const uniRouter = UNI_ROUTER.get(chainId);
  // await deploy("Periphery", {
  //   from: deployer,
  //   args: [
  //     divider.address,
  //     poolManager,
  //     uniFactory,
  //     uniRouter,
  //     "Sense Pool",
  //     false,
  //     ethers.utils.parseEther("0.051"),
  //     ethers.utils.parseEther("1"),
  //   ],
  //   log: true,
  // });
  // const periphery = await ethers.getContract("Periphery");
  // // Authorize the periphery on the divider
  // await divider.setPeriphery(periphery.address).then(tx => tx.wait());
};

module.exports.tags = ["prod:periphery", "scenario:prod"];
module.exports.dependencies = ["prod:feeds"];
