const { BALANCER_VAULT } = require("../../hardhat.addresses");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
  const balancerVault = BALANCER_VAULT.get(chainId);

  const divider = await ethers.getContract("Divider");
  const spaceFactory = await ethers.getContract("SpaceFactory");
  const poolManager = await ethers.getContract("PoolManager");

  console.log("\nDeploy Periphery");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManager.address, spaceFactory.address, balancerVault],
    log: true,
  });

  console.log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();

  console.log("Give the periphery auth over the pool manager");
  await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
};

module.exports.tags = ["prod:periphery", "scenario:prod"];
module.exports.dependencies = ["prod:space"];
