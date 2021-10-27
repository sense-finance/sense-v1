module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log("Deploy a simulated stable token named STABLE");
  await deploy("STABLE", {
    contract: "Token",
    from: deployer,
    args: ["STABLE", "STABLE", 18, deployer],
    log: true,
  });

  const stable = await ethers.getContract("STABLE");

  console.log("Mint the deployer a balance of 1,000,000 STABLE");
  await stable.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

  console.log("Deploy an asset deployer for the Divider will use");
  const { address: assetDeployerAddress } = await deploy("AssetDeployer", {
    from: deployer,
    args: [],
    log: true,
  });

  // set the cup to the zero address (where unclaimed rewards will go if nobody settles)
  const cup = ethers.constants.AddressZero;

  console.log("Deploy the divider");
  await deploy("Divider", {
    from: deployer,
    args: [stable.address, cup, assetDeployerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");
  const assetDeployer = await ethers.getContract("AssetDeployer");

  // console.log("Trust the dev address on the divider");
  // await divider.setIsTrusted(dev, true).then(tx => tx.wait());

  console.log("Add the divider to the asset deployer");
  await (await assetDeployer.init(divider.address)).wait();

  console.log("Deploy a mock pool manager");
  const { address: poolManagerAddress } = await deploy("MockPoolManager", {
    from: deployer,
    args: [],
    log: true,
  });

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
    args: [
      divider.address,
      poolManagerAddress,
      mockUniFactoryAddress,
      mockUniRouterAddress,
      "Sense Fuse Pool",
      false,
      0,
      0,
    ],
    log: true,
  });

  console.log("Set the periphery on the Divider");
  await (await divider.setPeriphery(peripheryAddress)).wait();
};

module.exports.tags = ["simulated:divider", "scenario:simulated"];
module.exports.dependencies = [];
