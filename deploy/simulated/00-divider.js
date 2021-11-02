module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log("Deploy a token hanlder for the Divider will use");
  const { address: tokenHandlerAddress } = await deploy("TokenHanlder", {
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
  const tokenHandler = await ethers.getContract("TokenHanlder");

  // console.log("Trust the dev address on the divider");
  // await divider.setIsTrusted(dev, true).then(tx => tx.wait());

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
    args: [
      mockFuseDirectoryAddress,
      mockComptrollerAddress,
      "0x2b3dD0AE288c13a730F6C422e2262a9d3dA79Ed1",
      divider.address,
      "0x1887118E49e0F4A78Bd71B792a49dE03504A764D",
    ],
    log: true,
  });
  const poolManager = await ethers.getContract("PoolManager");

  console.log("Deploy Sense Fuse pool via Pool Manager");
  await (
    await poolManager.deployPool(
      "Sense Fuse Pool",
      false,
      ethers.utils.parseEther("0.051"),
      ethers.utils.parseEther("1"),
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

  console.log("Deploy mocked uni dependencies");
  const { address: mockUniFactoryAddress } = await deploy("MockUniFactory", {
    from: deployer,
    args: [],
    log: true,
  });
  const { address: mockUniRouterAddress } = await deploy("MockUniSwapRouter", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy a Periphery with mocked dependencies");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManagerAddress, mockUniFactoryAddress, mockUniRouterAddress],
    log: true,
  });

  console.log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();

  console.log("Set the periphery on the PoolManager");
  await (await poolManager.setPeriphery(peripheryAddress)).wait();
};

module.exports.tags = ["simulated:divider", "scenario:simulated"];
module.exports.dependencies = [];
