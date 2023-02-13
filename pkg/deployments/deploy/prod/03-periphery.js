const { BALANCER_VAULT, PERMIT2, EXCHANGE_PROXY } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
  const balancerVault = BALANCER_VAULT.get(chainId);
  const permit2 = PERMIT2.get(chainId);
  const exchangeProxy = EXCHANGE_PROXY.get(chainId);

  const divider = await ethers.getContract("Divider", signer);
  const spaceFactory = await ethers.getContract("SpaceFactory", signer);
  const poolManager = await ethers.getContract("PoolManager", signer);

  log("\n-------------------------------------------------------");
  log("\nDeploy Periphery");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManager.address, spaceFactory.address, balancerVault, permit2, exchangeProxy],
    log: true,
  });

  log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();

  log("Give the periphery auth over the pool manager");
  if (!(await poolManager.isTrusted(peripheryAddress))) {
    await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
  }
};

module.exports.tags = ["prod:periphery", "scenario:prod"];
module.exports.dependencies = ["prod:space"];
