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

  console.log("Deploy a mocked Adapter implementation");
  const { address: mockAdapterImplAddress } = await deploy("MockAdapter", {
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
  const STAKE_SIZE = ethers.utils.parseEther("1");
  const MIN_MATURITY = "1209600"; // 2 weeks
  const MAX_MATURITY = "8467200"; // 14 weeks;
  const ORACLE = "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071";
  const MODE = 0;
  const factoryParams = [ORACLE, 0, ISSUANCE_FEE, stake.address, STAKE_SIZE, MIN_MATURITY, MAX_MATURITY, MODE];
  const { address: mockFactoryAddress } = await deploy("MockFactory", {
    from: deployer,
    args: [
      mockAdapterImplAddress,
      divider.address,
      factoryParams,
      airdrop.address,
    ],
    log: true,
  });

  console.log("Add mocked Factory as trusted in Divider");
  await (await divider.setIsTrusted(mockFactoryAddress, true)).wait();

  console.log("Add mocked Factory support to Periphery");
  await (await periphery.setFactory(mockFactoryAddress, true)).wait();

  const factory = await ethers.getContract("MockFactory");

  for (let targetName of global.TARGETS) {
    console.log(`Deploying simulated ${targetName}`);
    const underlyingAddress = "0x1111111111111111111111111111111111111111";
    await deploy(targetName, {
      contract: "MockTarget",
      from: deployer,
      args: [underlyingAddress, targetName, targetName, 18],
      log: true,
    });

    const target = await ethers.getContract(targetName);

    console.log(`Mint the deployer a balance of 1,000,000 ${targetName}`);
    await target.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

    console.log(`Add ${targetName} support for mocked Factory`);
    await (await factory.addTarget(target.address, true)).wait();

    const adapter = await periphery.callStatic.onboardAdapter(factory.address, target.address);
    console.log(`Onboard target ${target.address} via Periphery`);
    await (await periphery.onboardAdapter(factory.address, target.address)).wait();
    global.ADAPTERS[target.address] = adapter;

    console.log("Grant minting authority on the Reward token to the mock TWrapper");
    await (await airdrop.setIsTrusted(adapter, true)).wait();

    console.log(`Set ${targetName} issuance cap to max uint so we don't have to worry about it`);
    await divider.setGuard(target.address, ethers.constants.MaxUint256).then(tx => tx.wait());
  }
};

module.exports.tags = ["simulated:adapters", "scenario:simulated"];
module.exports.dependencies = ["simulated:divider"];
