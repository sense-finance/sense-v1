const { 
  FUSE_CERC20_IMPL, 
  MASTER_ORACLE_IMPL, 
  MASTER_ORACLE,
  INTEREST_RATE_MODEL,
} = require("../../hardhat.addresses");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  const divider = await ethers.getContract("Divider");

  console.log("\nDeploy mocked fuse & comp dependencies");
  const { address: mockComptrollerAddress } = await deploy("MockComptroller", {
    from: deployer,
    args: [],
    log: true,
  });
  const { address: mockFuseDirectoryAddress } = await deploy("MockFuseDirectory", {
    from: deployer,
    args: [mockComptrollerAddress],
    log: true,
  });

  console.log("\nDeploy a pool manager with mocked dependencies");
  await deploy("PoolManager", {
    from: deployer,
    args: [mockFuseDirectoryAddress, mockComptrollerAddress, FUSE_CERC20_IMPL.get(chainId), divider.address, MASTER_ORACLE_IMPL.get(chainId)],
    log: true,
  });
  const poolManager = await ethers.getContract("PoolManager");

  console.log("\nDeploy Sense Fuse pool via Pool Manager");
  await (
    await poolManager.deployPool(
      "Sense Pool",
      ethers.utils.parseEther("0.051"),
      ethers.utils.parseEther("1"),
      MASTER_ORACLE.get(chainId),
    )
  ).wait();

  console.log("Set target params via Pool Manager");
  const params = {
    irModel: INTEREST_RATE_MODEL.get(chainId),
    reserveFactor: ethers.utils.parseEther("0.1"),
    collateralFactor: ethers.utils.parseEther("0.5"),
    closeFactor: ethers.utils.parseEther("0.051"),
    liquidationIncentive: ethers.utils.parseEther("1"),
  };
  await (await poolManager.setParams(ethers.utils.formatBytes32String("TARGET_PARAMS"), params)).wait();

};

module.exports.tags = ["simulated:fuse", "scenario:simulated"];
module.exports.dependencies = ["simulated:divider"];
