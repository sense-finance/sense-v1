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

  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");
  const cup = DIVIDER_CUP.get(chainId);

  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy the divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");

  console.log("Trust the dev address on the divider");
  await (await divider.setIsTrusted(dev, true)).wait();

  const tokenHandler = await ethers.getContract("TokenHandler");
  console.log("Add the divider to the token hanlder");
  await (await tokenHandler.init(divider.address)).wait();
};

module.exports.tags = ["prod:divider", "scenario:prod"];
module.exports.dependencies = [];
