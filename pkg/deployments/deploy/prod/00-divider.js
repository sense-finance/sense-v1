const { DIVIDER_CUP } = require("../../hardhat.addresses");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");
  const cup = DIVIDER_CUP.get(chainId);

  console.log("\nDeploy the TokenHandler");
  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("\nDeploy the Divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");

  console.log("Trust the dev address on the divider");
  await (await divider.setIsTrusted(dev, true)).wait();

  const tokenHandler = await ethers.getContract("TokenHandler");
  console.log("Add the divider to the token handler");
  await (await tokenHandler.init(divider.address)).wait();
};

module.exports.tags = ["prod:divider", "scenario:prod"];
module.exports.dependencies = [];
