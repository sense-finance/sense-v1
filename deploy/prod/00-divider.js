const STAKE_TOKEN = new Map();
// DAI Mainnet
STAKE_TOKEN.set("1", "0x6b175474e89094c44da98b954eedeac495271d0f");
// DAI Local Mainnet fork
STAKE_TOKEN.set("111", "0x6b175474e89094c44da98b954eedeac495271d0f");
// TODO: Arbitrum
// UNISWAP_ROUTER.set("42161", "0x")

const DIVIDER_CUP = new Map();
// FIXME: real cup address (destination for unclaimed issuance fees)
DIVIDER_CUP.set("1", "0x0000000000000000000000000000000000000000");
// Local Mainnet fork
DIVIDER_CUP.set("111", "0x0000000000000000000000000000000000000000");
// TODO: Arbitrum
// DIVIDER_CUP.set("42161", "0x")

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!STAKE_TOKEN.has(chainId)) throw Error("No stake token found");
  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");

  const stake = STAKE_TOKEN.get(chainId);
  const cup = DIVIDER_CUP.get(chainId);

  const { address: assetDeployerAddress } = await deploy("AssetDeployer", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy the divider");
  await deploy("Divider", {
    from: deployer,
    args: [stake, cup, assetDeployerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");

  console.log("Trust the dev address on the divider");
  await (await divider.setIsTrusted(dev, true)).wait();

  const assetDeployer = await ethers.getContract("AssetDeployer");
  console.log("Add the divider to the asset deployer");
  await (await assetDeployer.init(divider.address)).wait();
};

module.exports.tags = ["prod:divider", "scenario:prod"];
module.exports.dependencies = [];
