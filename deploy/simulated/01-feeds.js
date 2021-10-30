module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const divider = await ethers.getContract("Divider");
  const periphery = await ethers.getContract("Periphery");

  console.log("Deploy a simulated stake token named STAKE");
  await deploy("STAKE", {
    contract: "Token",
    from: deployer,
    args: ["STAKE", "STAKE", 18, deployer],
    log: true,
  });

  const stake = await ethers.getContract("STAKE");

  console.log("Mint the deployer a balance of 1,000,000 STAKE");
  await stake.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

  console.log("Deploy a mocked Feed implementation");
  const { address: mockFeedImplAddress } = await deploy("MockFeed", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy a mocked TWrapper implementation");
  const { address: mockTwrapperImplAddress } = await deploy("MockTWrapper", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy a simulated airdrop reward token named Airdrop");
  await deploy("Airdrop", {
    contract: "Token",
    from: deployer,
    args: ["Aidrop Reward Token", "ADP", 18, deployer],
    log: true,
  });

  const airdrop = await ethers.getContract("Airdrop");

  console.log("Deploy a mocked Factory with mocked dependencies");

  const ISSUANCE_FEE = ethers.utils.parseEther("0.01");
  const INIT_STAKE = ethers.utils.parseEther("1");
  const MIN_MATURITY = "1209600"; // 2 weeks
  const MAX_MATURITY = "8467200"; // 14 weeks;
  const { address: mockFactoryAddress } = await deploy("MockFactory", {
    from: deployer,
    args: [mockFeedImplAddress, mockTwrapperImplAddress, divider.address, 0, airdrop.address, stake.address, ISSUANCE_FEE, INIT_STAKE, MIN_MATURITY, MAX_MATURITY ],
    log: true,
  });

  console.log("Add mocked Factory as trusted in Divider");
  await (await divider.setIsTrusted(mockFactoryAddress, true)).wait();

  console.log("Add mocked Factory support to Periphery");
  await (await periphery.setFactory(mockFactoryAddress, true)).wait();

  const factory = await ethers.getContract("MockFactory");

  for (let targetName of global.TARGETS) {
    console.log(`Deploying simulated ${targetName}`);
    await deploy(targetName, {
      contract: "Token",
      from: deployer,
      args: [targetName, targetName, 18, deployer],
      log: true,
    });

    const target = await ethers.getContract(targetName);

    console.log(`Mint the deployer a balance of 1,000,000 ${targetName}`);
    await target.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

    console.log(`Add ${targetName} support for mocked Factory`);
    await (await factory.addTarget(target.address, true)).wait();

    const { wtClone } = await periphery.callStatic.onboardFeed(factory.address, target.address);
    console.log(`Onboard target ${target.address} via Periphery`);
    await (await periphery.onboardFeed(factory.address, target.address)).wait();

    console.log("Grant minting authority on the Reward token to the mock TWrapper");
    await (await airdrop.setIsTrusted(wtClone, true)).wait();

    console.log(`Set ${targetName} issuance cap to max uint so we don't have to worry about it`);
    await divider.setGuard(target.address, ethers.constants.MaxUint256).then(tx => tx.wait());
  }
};

module.exports.tags = ["simulated:feeds", "scenario:simulated"];
module.exports.dependencies = ["simulated:divider"];
