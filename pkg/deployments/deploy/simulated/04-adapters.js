const { OZ_RELAYER } = require("../../hardhat.addresses");
const {
  moveDeployments,
  writeDeploymentsToFile,
  writeAdaptersToFile,
  getDeployedAdapters,
} = require("../../hardhat.utils");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  const divider = await ethers.getContract("Divider", signer);
  const periphery = await ethers.getContract("Periphery", signer);

  log("\n-------------------------------------------------------");
  log("DEPLOY DEPENDENCIES, FACTORIES & ADAPTERS");
  log("-------------------------------------------------------");

  const stake = await deployStake();
  const airdrop = await deployAirdrop();

  const underlyingNames = new Set();

  for (let factory of global.dev.FACTORIES) {
    const { contractName: factoryContractName, ifee, stakeSize, minm, maxm, mode, oracle, tilt, targets } = factory(chainId);
    log(`\nDeploy ${factoryContractName} with mocked dependencies`);
    // Large enough to not be a problem, but won't overflow on ModAdapter.fmul
    const factoryParams = [oracle, ifee, stake.address, stakeSize, minm, maxm, mode, tilt];
    const { address: mockFactoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams, airdrop.address],
      log: true,
    });

    log(`Trust ${factoryContractName} on the divider`);
    await (await divider.setIsTrusted(mockFactoryAddress, true)).wait();

    log(`Add ${factoryContractName} support to Periphery`);
    if (!(await periphery.factories(mockFactoryAddress))) {
      await (await periphery.setFactory(mockFactoryAddress, true)).wait();
    }

    await deploy("MultiMint", {
      from: deployer,
      args: [],
      log: true,
    });

    log("\n-------------------------------------------------------");
    log(`DEPLOY UNDERLYINGS, TARGETS & ADAPTERS FOR: ${factoryContractName}`);
    log("---------------------------------------------------------");
    for (let t of targets) {
      await deployAdapter(t, factoryContractName);
    }
  }

  log("\n-------------------------------------------------------")
  log("DEPLOY ADAPTERS WITHOUT FACTORY")
  log("-------------------------------------------------------")
  for (let adapter of global.dev.ADAPTERS) {
    // if (!stake) throw Error("No stake token found");
    await deployAdapter(adapter(chainId), null);
  }

  if (!process.env.CI && hre.config.networks[network.name].saveDeployments) {
    log("\n-------------------------------------------------------");
    await moveDeployments();
    await writeDeploymentsToFile();
    await writeAdaptersToFile();
  }

  // Helpers
  async function deployAdapter(t, factory) {  
      const targetName = factory? t.name : t.target.name;
      log(`\nDeploy simulated ${targetName}`);

      const underlying = await getUnderlyingForTarget(targetName);
      const targetContract = await deployTarget(targetName, underlying.address);
      await new Promise(res => setTimeout(res, 500));

      log("Give the multi minter permission on Target");
      const multiMint = await ethers.getContract("MultiMint", signer);
      await (await targetContract.setIsTrusted(multiMint.address, true)).wait();

      log(`Mint the deployer a balance of 10,000,000 ${targetName}`);
      await multiMint.mint([targetContract.address], [ethers.utils.parseEther("10000000")], deployer).then(tx => tx.wait());

      let adapterAddress = (await getDeployedAdapters())[targetName];
      if (!adapterAddress) {
        log(`Deploy adapter for ${targetName}`);
        if (factory) {
          adapterAddress = await deployAdapterViaFactory(targetName, targetContract, factory);
        } else {
          adapterAddress = await deployAdapterWithoutFactory(t, targetContract);
        }
      } else {
        log(`Adapter for ${targetName} already deployed, skipping...`)
      }

      log("Give the adapter minter permission on Target");
      await (await targetContract.setIsTrusted(adapterAddress, true)).wait();

      log("Give the adapter minter permission on Underlying");
      await (await underlying.setIsTrusted(adapterAddress, true)).wait();

      log("Grant minting authority on the Reward token to the mock TWrapper");
      await (await airdrop.setIsTrusted(adapterAddress, true)).wait();

      log(`Set ${targetName} adapter issuance cap to max uint so we don't have to worry about it`);
      await divider.setGuard(adapterAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

      log(`Can call and set scale value`);
      await setScale(adapterAddress);
  }

  async function getUnderlyingForTarget(targetName) {
    const underlyingRegexRes = targetName.match(/[^A-Z]*(.*)/);
    const matchedName = underlyingRegexRes && underlyingRegexRes[1];
    const underlyingName = matchedName === "ETH" ? "WETH" : matchedName || `UNDERLYING-${targetName}`;

    if (!underlyingNames.has(underlyingName)) {
      await deploy(underlyingName, {
        contract: "AuthdMockToken",
        from: deployer,
        args: [underlyingName, underlyingName, 18],
        log: true,
      });

      underlyingNames.add(underlyingName);
    }
    return await ethers.getContract(underlyingName, signer);
  }

  async function deployTarget(targetName, underlyingAddress) {
    await deploy(targetName, {
      contract: "AuthdMockTarget",
      from: deployer,
      args: [underlyingAddress, targetName, targetName, 18],
      log: true,
    });
    return await ethers.getContract(targetName, signer);
  }

  async function deployAdapterViaFactory(targetName, targetContract, factory) {
    const targetAddress = targetContract.address;
    const factoryContract = await ethers.getContract(factory, signer);
    const factoryAddress = factoryContract.address;
    log(`Add ${targetName} support for mocked Factory`);
    if (!(await factoryContract.targets(targetAddress))) {
      await (await factoryContract.addTarget(targetAddress, true)).wait();
    }
    const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, targetAddress);
    log(`Onboard target ${targetName} via Periphery`);
    await (await periphery.deployAdapter(factoryAddress, targetAddress)).wait();
    return adapterAddress;
  }

  async function deployAdapterWithoutFactory(t, targetContract) {
    let { contractName, deploymentParams, target } = t;
    deploymentParams.target = targetContract.address;
    deploymentParams.stake = stake.address;
    deploymentParams.reward = airdrop.address;

    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, ...Object.values(deploymentParams)],
      log: true,
    });

    log(`Set ${contractName} adapter issuance cap to ${target.guard}`);
    await divider.setGuard(adapterAddress, target.guard).then(tx => tx.wait());
    
    log(`Verify ${contractName} adapter`);
    await periphery.verifyAdapter(adapterAddress, true).then(tx => tx.wait());

    log(`Onboard ${contractName} adapter`);
    await periphery.onboardAdapter(adapterAddress, true).then(tx => tx.wait());

    return adapterAddress;
  }

  async function setScale(adapterAddress) {
    const { abi: adapterAbi } = await deployments.getArtifact("MockAdapter");
    const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
    const scale = await adapter.callStatic.scale();
    log(`-> scale: ${scale.toString()}`);
    await adapter.setScale(ethers.utils.parseEther("1.1")).then(tx => tx.wait());
  }

  async function deployStake() {
    log("\nDeploy a simulated stake token named STAKE");
    await deploy("STAKE", {
      contract: "Token",
      from: deployer,
      args: ["STAKE", "STAKE", 18, deployer],
      log: true,
    });
    const stake = await ethers.getContract("STAKE", signer);

    log("Mint the deployer a balance of 1,000,000 STAKE");
    await stake.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

    log("Mint the relayer a balance of 1,000,000 STAKE");
    await stake.mint(OZ_RELAYER.get(chainId), ethers.utils.parseEther("1000000")).then(tx => tx.wait());

    return stake;
  }
  async function deployAirdrop() {
    log("\nDeploy a simulated airdrop reward token named Airdrop");
    await deploy("Airdrop", {
      contract: "Token",
      from: deployer,
      args: ["Aidrop Reward Token", "ADP", 18, deployer],
      log: true,
    });
    return await ethers.getContract("Airdrop", signer);
  }
};

module.exports.tags = ["simulated:adapters", "scenario:simulated"];
module.exports.dependencies = ["simulated:periphery"];
