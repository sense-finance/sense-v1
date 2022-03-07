const { DIVIDER_CUP } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  if (!DIVIDER_CUP.has(chainId)) throw Error("No cup found");
  const cup = DIVIDER_CUP.get(chainId);

  console.log(`Deploying from ${deployer}`);

  log("\n-------------------------------------------------------");
  log("\nDeploy the TokenHandler");
  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  log("\n-------------------------------------------------------");
  log("\nDeploy the Divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider", signer);
  const tokenHandler = await ethers.getContract("TokenHandler", signer);
  log("Add the divider to the token handler");
  await (await tokenHandler.init(divider.address)).wait();
};

module.exports.tags = ["prod:divider", "scenario:prod"];
module.exports.dependencies = [];
