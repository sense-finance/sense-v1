const fs = require("fs");
const { exec } = require("child_process");

module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const signer = await ethers.getSigner(deployer);

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
  const MIN_MATURITY = "0";
  const MAX_MATURITY = "4838400"; // 4 weeks;
  const ORACLE = "0x6D2299C48a8dD07a872FDd0F8233924872Ad1071";
  const MODE = 1; // 1 for weekly
  const TILT = 0;
  // Large enough to not be a problem, but won't overflow on ModAdapter.fmul
  const factoryParams = [ORACLE, ISSUANCE_FEE, stake.address, STAKE_SIZE, MIN_MATURITY, MAX_MATURITY, MODE, TILT];
  const { address: mockFactoryAddress } = await deploy("MockFactory", {
    from: deployer,
    args: [divider.address, factoryParams, airdrop.address],
    log: true,
  });

  console.log("Add mocked Factory as trusted in Divider");
  await (await divider.setIsTrusted(mockFactoryAddress, true)).wait();

  console.log("Add mocked Factory support to Periphery");
  await (await periphery.setFactory(mockFactoryAddress, true)).wait();

  const factory = await ethers.getContract("MockFactory");

  await deploy("MultiMint", {
    from: deployer,
    args: [],
    log: true,
  });

  const multiMint = await ethers.getContract("MultiMint");

  const underlyingAddresses = {};
  console.log("Deploying Targets & Adapters");
  for (let targetName of global.TARGETS) {
    console.log(`Deploying simulated ${targetName}`);
    const underlyingRegexRes = targetName.match(/[^A-Z]*(.*)/);
    const underlyingName = (underlyingRegexRes && underlyingRegexRes[1]) || `UNDERLYING-${targetName}`;
    const underlyingAddress = underlyingAddresses[underlyingName];

    let mockUnderlyingAddress = underlyingAddress;
    if (!underlyingAddress) {
      mockUnderlyingAddress = (
        await deploy(underlyingName, {
          contract: "AuthdMockToken",
          from: deployer,
          args: [underlyingName, underlyingName, 18],
          log: true,
        })
      ).address;
    }

    const underlying = await ethers.getContract(underlyingName);

    await deploy(targetName, {
      contract: "AuthdMockTarget",
      from: deployer,
      args: [mockUnderlyingAddress, targetName, targetName, 18],
      log: true,
    });

    const target = await ethers.getContract(targetName);

    await new Promise(res => setTimeout(res, 500));

    console.log("Give the multi minter permission on Target");
    await (await target.setIsTrusted(multiMint.address, true)).wait();

    console.log(`Mint the deployer a balance of 10,000,000 ${targetName}`);
    await multiMint.mint([target.address], [ethers.utils.parseEther("10000000")], deployer).then(tx => tx.wait());

    console.log(`Add ${targetName} support for mocked Factory`);
    await (await factory.addTarget(target.address, true)).wait();

    const adapterAddress = await periphery.callStatic.onboardAdapter(factory.address, target.address);
    console.log(`Onboard target ${target.address} via Periphery`);
    await (await periphery.onboardAdapter(factory.address, target.address)).wait();
    global.ADAPTERS[targetName] = adapterAddress;

    console.log("Give the adapter minter permission on Target");
    await (await target.setIsTrusted(adapterAddress, true)).wait();

    console.log("Give the adapter minter permission on Underlying");
    await (await underlying.setIsTrusted(adapterAddress, true)).wait();

    console.log("Grant minting authority on the Reward token to the mock TWrapper");
    await (await airdrop.setIsTrusted(adapterAddress, true)).wait();

    console.log(`Set ${targetName} adapter issuance cap to max uint so we don't have to worry about it`);
    await divider.setGuard(adapterAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

    console.log(`Can call scale value`);
    const { abi: adapterAbi } = await deployments.getArtifact("MockAdapter");
    const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
    const scale = await adapter.callStatic.scale();
    console.log(scale.toString(), "scale");
    await adapter.setScale(ethers.utils.parseEther("1.1")).then(tx => tx.wait());
  }

  const { abi: adapterAbi } = await deployments.getArtifact("MockAdapter");

  if (!process.env.CI) {
    const currentTag = await new Promise((resolve, reject) => {
      exec("git describe --abbrev=0", (error, stdout, stderr) => {
        if (error) {
          reject(error);
        }
        resolve(stdout ? stdout : stderr);
      });
    });

    const deploymentDir = `./adapter-deployments/${currentTag.trim().replace(/(\r\n|\n|\r)/gm, "")}/`;
    fs.mkdirSync(deploymentDir, { recursive: true });
    fs.writeFileSync(`./${deploymentDir}/adapters.json`, JSON.stringify({ addresses: global.ADAPTERS, adapterAbi }));
  }
};

module.exports.tags = ["simulated:adapters", "scenario:simulated"];
module.exports.dependencies = ["simulated:divider"];
