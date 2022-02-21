module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const divider = await ethers.getContract("Divider");
  const poolManager = await ethers.getContract("PoolManager");
  const balancerVault = await ethers.getContract("Vault");
  const spaceFactory = await ethers.getContract("SpaceFactory");

  console.log("\nDeploy a Periphery with mocked dependencies");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManager.address, spaceFactory.address, balancerVault.address],
    log: true,
  });

  console.log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();

  console.log("Give the periphery auth over the pool manager");
  await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
};

module.exports.tags = ["simulated:periphery", "scenario:simulated"];
module.exports.dependencies = ["simulated:space"];
