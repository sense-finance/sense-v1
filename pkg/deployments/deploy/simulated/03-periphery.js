const { PERMIT2, EXCHANGE_PROXY } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  const divider = await ethers.getContract("Divider", signer);
  const poolManager = await ethers.getContract("PoolManager", signer);
  const balancerVault = await ethers.getContract("Vault", signer);
  const spaceFactory = await ethers.getContract("SpaceFactory", signer);

  log("\n-------------------------------------------------------");
  log("\nDeploy a Periphery with mocked dependencies");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [
      divider.address,
      poolManager.address,
      spaceFactory.address,
      balancerVault.address,
      PERMIT2.get(chainId),
      EXCHANGE_PROXY.get(chainId),
    ],
    log: true,
  });

  log("Set the periphery on the Divider");
  if ((await divider.periphery()) !== peripheryAddress) {
    await (await divider.setPeriphery(peripheryAddress)).wait();
  }

  log("Give the periphery auth over the pool manager");
  if (!(await poolManager.isTrusted(peripheryAddress))) {
    await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
  }
};

module.exports.tags = ["simulated:periphery", "scenario:simulated"];
module.exports.dependencies = ["simulated:space"];
