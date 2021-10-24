const STABLE_TOKEN = new Map();
// DAI Mainnet
STABLE_TOKEN.set("1", "0x6b175474e89094c44da98b954eedeac495271d0f");
// DAI Local Mainnet fork
STABLE_TOKEN.set("111", "0x6b175474e89094c44da98b954eedeac495271d0f");
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

  if (!STABLE_TOKEN.has(chainId)) throw Error("No stable token found");
  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");

  const stable = STABLE_TOKEN.get(chainId);
  const cup = DIVIDER_CUP.get(chainId);

  console.log("Deploy the divider");
  await deploy("Divider", {
    from: deployer,
    args: [stable, cup],
    log: true,
  });

  const divider = await ethers.getContract("Divider");

  console.log("Trust the dev address on the divider");
  await (await divider.setIsTrusted(dev, true)).wait();
};

module.exports.tags = ["Divider"];
module.exports.dependencies = [];
