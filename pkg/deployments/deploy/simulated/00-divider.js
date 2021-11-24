const fs = require("fs");

const MASTER_ORACLE_IMPL = "0xb3c8ee7309be658c186f986388c2377da436d8fb";
const FUSE_CERC20_IMPL = "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9";
const RARI_MASTER_ORACLE = "0x1887118E49e0F4A78Bd71B792a49dE03504A764D";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // for Space
  const TS = ethers.utils.parseEther("1").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("31622400"));
  const G1 = ethers.utils.parseEther("950").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("1000"));
  const G2 = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("950"));

  // IMPORTANT: this must be run *first*, so that it has the same address across deployments
  // (has the same deployment address and nonce)
  const pkgjson = JSON.parse(fs.readFileSync(`${__dirname}/../../package.json`, "utf-8"));
  await deploy("Versioning", {
    from: deployer,
    args: [pkgjson.version],
    log: true,
  });

  const versioning = await ethers.getContract("Versioning");
  console.log("Deploying Sense version", await versioning.version());

  console.log("Deploy a token handler for the Divider will use");
  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  // set the cup to the zero address (where unclaimed rewards will go if nobody settles)
  const cup = ethers.constants.AddressZero;

  console.log("Deploy the divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");
  const tokenHandler = await ethers.getContract("TokenHandler");

  console.log("Add the divider to the asset deployer");
  await (await tokenHandler.init(divider.address)).wait();

  console.log("Deploy mocked fuse & comp dependencies");
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

  console.log("Deploy a pool manager with mocked dependencies");
  const { address: poolManagerAddress } = await deploy("PoolManager", {
    from: deployer,
    args: [mockFuseDirectoryAddress, mockComptrollerAddress, FUSE_CERC20_IMPL, divider.address, MASTER_ORACLE_IMPL],
    log: true,
  });
  const poolManager = await ethers.getContract("PoolManager");

  console.log("Deploy Sense Fuse pool via Pool Manager");
  await (
    await poolManager.deployPool(
      "Sense Pool",
      ethers.utils.parseEther("0.051"),
      ethers.utils.parseEther("1"),
      RARI_MASTER_ORACLE,
    )
  ).wait();

  console.log("Set target params via Pool Manager");
  const params = {
    irModel: "0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7",
    reserveFactor: ethers.utils.parseEther("0.1"),
    collateralFactor: ethers.utils.parseEther("0.5"),
    closeFactor: ethers.utils.parseEther("0.051"),
    liquidationIncentive: ethers.utils.parseEther("1"),
  };
  await (await poolManager.setParams(ethers.utils.formatBytes32String("TARGET_PARAMS"), params)).wait();

  console.log("Deploy Space & Space dependencies");
  const { address: authorizerAddress } = await deploy("Authorizer", {
    from: deployer,
    args: [deployer],
    log: true,
  });
  const { address: balancerVaultAddress } = await deploy("Vault", {
    from: deployer,
    args: [authorizerAddress, WETH, 0, 0],
    log: true,
  });

  const { address: spaceFactory } = await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVaultAddress, divider.address, TS, G1, G2],
    log: true,
  });

  console.log("Deploy a Periphery with mocked dependencies");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManagerAddress, spaceFactory, balancerVaultAddress],
    log: true,
  });

  console.log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();

  console.log("Give the periphery auth over the pool manager");
  await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
};

module.exports.tags = ["simulated:divider", "scenario:simulated"];
module.exports.dependencies = [];
