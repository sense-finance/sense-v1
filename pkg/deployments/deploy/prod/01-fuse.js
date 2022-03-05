const {
  FUSE_POOL_DIR,
  FUSE_COMPTROLLER_IMPL,
  FUSE_CERC20_IMPL,
  MASTER_ORACLE_IMPL,
  MASTER_ORACLE,
  INTEREST_RATE_MODEL,
} = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;
  const chainId = await getChainId();

  if (!FUSE_POOL_DIR.has(chainId)) throw Error("No fuse directory found");
  if (!FUSE_COMPTROLLER_IMPL.has(chainId)) throw Error("No fuse comptroller found");
  if (!FUSE_CERC20_IMPL.has(chainId)) throw Error("No fuse cerc20 found");
  if (!MASTER_ORACLE_IMPL.has(chainId)) throw Error("No fuse master oracle implementation found");
  if (!MASTER_ORACLE.has(chainId)) throw Error("No fuse master oracle found");
  if (!INTEREST_RATE_MODEL.has(chainId)) throw Error("No fuse interest rate model found");
  const fusePoolDir = FUSE_POOL_DIR.get(chainId);
  const comptrollerImpl = FUSE_COMPTROLLER_IMPL.get(chainId);
  const fuseCERC20Impl = FUSE_CERC20_IMPL.get(chainId);
  const masterOracleImpl = MASTER_ORACLE_IMPL.get(chainId);
  const masterOracle = MASTER_ORACLE.get(chainId);
  const interestRateModel = INTEREST_RATE_MODEL.get(chainId);

  const divider = await ethers.getContract("Divider");

  log("\n-------------------------------------------------------");
  log("\nDeploy the Fuse Pool Manager");
  await deploy("PoolManager", {
    from: deployer,
    args: [fusePoolDir, comptrollerImpl, fuseCERC20Impl, divider.address, masterOracleImpl],
    log: true,
  });

  log("\n-------------------------------------------------------");
  log("\nDeploy Sense Fuse pool via Pool Manager");
  const poolManager = await ethers.getContract("PoolManager");
  await (
    await poolManager.deployPool(
      "Sense Pool – Core",
      ethers.utils.parseEther("0.333"),
      ethers.utils.parseEther("1.08"),
      masterOracle,
    )
  ).wait();

  log("Set target params via Pool Manager");
  const targetParams = {
    irModel: interestRateModel, // TODO(launch)
    reserveFactor: ethers.utils.parseEther("0"),
    collateralFactor: ethers.utils.parseEther("0.5"),
  };
  await (await poolManager.setParams(ethers.utils.formatBytes32String("TARGET_PARAMS"), targetParams)).wait();

  const ptParams = {
    irModel: interestRateModel, // TODO(launch)
    reserveFactor: ethers.utils.parseEther("0"),
    collateralFactor: ethers.utils.parseEther("0.5"),
  };
  await (await poolManager.setParams(ethers.utils.formatBytes32String("PT_PARAMS"), ptParams)).wait();

  const lpParams = {
    irModel: interestRateModel, // TODO(launch)
    reserveFactor: ethers.utils.parseEther("0"),
    collateralFactor: ethers.utils.parseEther("0.5"),
  };
  await (await poolManager.setParams(ethers.utils.formatBytes32String("LP_TOKEN_PARAMS"), lpParams)).wait();
};

module.exports.tags = ["prod:fuse", "scenario:prod"];
module.exports.dependencies = ["prod:divider"];
