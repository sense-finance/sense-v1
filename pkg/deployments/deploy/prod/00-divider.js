const { DIVIDER_CUP } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");
  const cup = DIVIDER_CUP.get(chainId);

  log("\n-------------------------------------------------------")
  log("\nDeploy the TokenHandler");
  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  log("\n-------------------------------------------------------")
  log("\nDeploy the Divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");
  const tokenHandler = await ethers.getContract("TokenHandler");
  log("Add the divider to the token handler");
  await (await tokenHandler.init(divider.address)).wait();
};

module.exports.tags = ["prod:divider", "scenario:prod"];
module.exports.dependencies = [];
