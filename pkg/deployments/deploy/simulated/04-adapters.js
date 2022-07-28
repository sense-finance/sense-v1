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

  await deploy("MultiMint", {
    from: deployer,
    args: [],
    log: true,
  });

  for (let factory of global.dev.FACTORIES) {
    const { contractName: factoryContractName, oracle, stakeSize, minm, maxm, ifee, mode, tilt, targets, noncrop, crops, is4626 } = factory(chainId);
    log(`\nDeploy ${factoryContractName} with mocked dependencies`);
    // Large enough to not be a problem, but won't overflow on ModAdapter.fmul
    const factoryParams = [oracle, stake.address, stakeSize, minm, maxm, ifee, mode, tilt];
    const { address: mockFactoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams, ...(noncrop ? [] : crops ? [[airdrop.address]] : [airdrop.address])],
      log: true,
    });

    log(`Trust ${factoryContractName} on the divider`);
    if (!(await divider.isTrusted(mockFactoryAddress))) {
      await (await divider.setIsTrusted(mockFactoryAddress, true)).wait();
    }

    log(`Add ${factoryContractName} support to Periphery`);
    if (!(await periphery.factories(mockFactoryAddress))) {
      await (await periphery.setFactory(mockFactoryAddress, true)).wait();
    }

    log("\n-------------------------------------------------------");
    log(`DEPLOY UNDERLYINGS, TARGETS & ADAPTERS FOR: ${factoryContractName}`);
    log("---------------------------------------------------------");
    for (let t of targets) {
      is4626 ? await deploy4626Adapter(t, factoryContractName) : await deployAdapter(t, factoryContractName);
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
      const { name: tName, tDecimals, uDecimals, comptroller: data } = factory ? t : t.target;
      
      log(`\nDeploy simulated ${tName} with ${tDecimals} decimals`);

      const underlying = await getUnderlyingForTarget(tName, uDecimals);
      const targetContract = await deployTarget(tName, tDecimals, underlying.address);

      await new Promise(res => setTimeout(res, 500));
      
      // as target is not an ERC-4626, we just directly mint target
      const multiMint = await ethers.getContract("MultiMint", signer);
      log("Give the multi minter permission on Target");
      if (!(await targetContract.isTrusted(multiMint.address))) {
        await (await targetContract.setIsTrusted(multiMint.address, true)).wait();
      }

      log(`Mint the deployer a balance of 10,000,000 ${tName}`);
      if (!(await targetContract.balanceOf(deployer)).gte(ethers.utils.parseEther("10000000"))) {
        await multiMint.mint([targetContract.address], [ethers.utils.parseEther("10000000")], deployer).then(tx => tx.wait());
      }

      let adapterAddress = (await getDeployedAdapters())[tName];
      if (!adapterAddress) {
        log(`Deploy adapter for ${tName}`);
        if (factory) {
          adapterAddress = await deployAdapterViaFactory(tName, targetContract, data, factory);
        } else {
          adapterAddress = await deployAdapterWithoutFactory(t, targetContract);
        }
      } else {
        log(`Adapter for ${tName} already deployed, skipping...`)
      }

      log("Give the adapter minter permission on Target");
      if (!(await targetContract.isTrusted(adapterAddress))) {
        await (await targetContract.setIsTrusted(adapterAddress, true)).wait();
      }

      log("Give the adapter minter permission on Underlying");
      if (!(await underlying.isTrusted(adapterAddress))) {
        await (await underlying.setIsTrusted(adapterAddress, true)).wait();
      }

      log("Grant minting authority on the Reward token to the mock TWrapper");
      if (!(await airdrop.isTrusted(adapterAddress))) {
        await (await airdrop.setIsTrusted(adapterAddress, true)).wait();
      }

      log(`Set ${tName} adapter issuance cap to max uint so we don't have to worry about it`);
      if (!((await divider.adapterMeta(adapterAddress)).guard.eq(ethers.constants.MaxUint256))) {
        await divider.setGuard(adapterAddress, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      const { abi: adapterAbi } = await deployments.getArtifact("MockAdapter");
      const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);  

      log(`Can call scale`);
      const scale = await adapter.callStatic.scale();
      log(`-> scale value: ${scale.toString()}`);

      log(`Can set scale value`);
      if (!scale.eq(ethers.utils.parseEther("1.1"))) {
        await adapter.setScale(ethers.utils.parseEther("1.1")).then(tx => tx.wait());
      }
  }

  async function deploy4626Adapter(t, factory) {  
    const { name: tName, tDecimals, uDecimals, comptroller: data } = factory ? t : t.target;
    
    log(`\nDeploy simulated ${tName} with ${tDecimals} decimals (ERC-4626)`);

    const underlying = await getUnderlyingForTarget(tName, uDecimals);
    const targetContract = await deploy4626Target(tName, underlying.address);

    await new Promise(res => setTimeout(res, 500));
    
    // as target is ERC-4626, we mint underlying and deposit on vault so as to get target
    const multiMint = await ethers.getContract("MultiMint", signer);

    log("Give the multi minter permission on Underlying");
    if (!(await underlying.isTrusted(multiMint.address))) {
      await (await underlying.setIsTrusted(multiMint.address, true)).wait();
    }

    log(`Mint the deployer a balance of 10,000,000 ${await underlying.name()}`);
    if (!(await underlying.balanceOf(deployer)).gte(ethers.utils.parseEther("10000000"))) {
      await multiMint.mint([underlying.address], [ethers.utils.parseEther("10000000")], deployer).then(tx => tx.wait());
      log(`Deposit 10,000,000 ${await underlying.name()} on ${await targetContract.name()} ERC4626 vault`);
      await underlying.approve(targetContract.address, ethers.utils.parseEther("10000000"));
      await targetContract.deposit(await underlying.balanceOf(deployer), deployer).then(tx => tx.wait());
    }

    let adapterAddress = (await getDeployedAdapters())[tName];
    if (!adapterAddress) {
      log(`Deploy adapter for ${tName}`);
      if (factory) {
        adapterAddress = await deployAdapterViaFactory(tName, targetContract, data, factory);
      } else {
        adapterAddress = await deployAdapterWithoutFactory(t, targetContract);
      }
    } else {
      log(`Adapter for ${tName} already deployed, skipping...`)
    }

    log("Give the adapter minter permission on Underlying");
    if (!(await underlying.isTrusted(adapterAddress))) {
      await (await underlying.setIsTrusted(adapterAddress, true)).wait();
    }

    log("Grant minting authority on the Reward token to the mock TWrapper");
    if (!(await airdrop.isTrusted(adapterAddress))) {
      await (await airdrop.setIsTrusted(adapterAddress, true)).wait();
    }

    log(`Set ${tName} adapter issuance cap to max uint so we don't have to worry about it`);
    if (!((await divider.adapterMeta(adapterAddress)).guard.eq(ethers.constants.MaxUint256))) {
      await divider.setGuard(adapterAddress, ethers.constants.MaxUint256).then(tx => tx.wait());
    }

    const { abi: adapterAbi } = await deployments.getArtifact("MockAdapter");
    const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);  

    log(`Can call scale`);
    const scale = await adapter.callStatic.scale();
    log(`-> scale value: ${scale.toString()}`);
}

  async function getUnderlyingForTarget(targetName, uDecimals) {
    const underlyingRegexRes = targetName.match(/[^A-Z]*(.*)/);
    const matchedName = underlyingRegexRes && underlyingRegexRes[1];
    const underlyingName = matchedName === "ETH" ? "WETH" : matchedName || `UNDERLYING-${targetName}`;

    if (!underlyingNames.has(underlyingName)) {
      log(`Deploy simulated underlying ${underlyingName} with ${uDecimals} decimals`);
      await deploy(underlyingName, {
        contract: "AuthdMockToken",
        from: deployer,
        args: [underlyingName, underlyingName, uDecimals],
        log: true,
      });

      underlyingNames.add(underlyingName);
    }
    return await ethers.getContract(underlyingName, signer);
  }

  async function deploy4626Target(targetName, underlyingAddress) {
    await deploy(targetName, {
      contract: "MockERC4626",
      from: deployer,
      args: [underlyingAddress, targetName, targetName],
      log: true,
    });
    return await ethers.getContract(targetName, signer);
    
  }

  async function deployTarget(targetName, tDecimals, underlyingAddress) {
    await deploy(targetName, {
      contract: "AuthdMockTarget",
      from: deployer,
      args: [underlyingAddress, targetName, targetName, tDecimals],
      log: true,
    });
    const target = await ethers.getContract(targetName, signer);
    log(`Give Relayer permission to mint target`);
    if (!(await target.isTrusted(OZ_RELAYER.get(chainId)))) {
      await target.setIsTrusted(OZ_RELAYER.get(chainId), true);
    }
    return target;
  }

  async function deployAdapterViaFactory(targetName, targetContract, data, factory) {
    const targetAddress = targetContract.address;
    const factoryContract = await ethers.getContract(factory, signer);
    const factoryAddress = factoryContract.address;
    log(`Add ${targetName} support for mocked Factory`);
    if (!data) data = "0x";
    if (!(await factoryContract.targets(targetAddress))) {
      await (await factoryContract.supportTarget(targetAddress, true)).wait();
    }
    if (data !== "0x") {
      data = ethers.utils.defaultAbiCoder.encode(["address"], [data]);
    }
    const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, targetAddress, data);
    log(`Onboard target ${targetName} via Periphery`);
    await (await periphery.deployAdapter(factoryAddress, targetAddress, data)).wait();
    return adapterAddress;
  }

  async function deployAdapterWithoutFactory(t, targetContract) {
    let { contractName, adapterParams, target, underlying, ifee } = t;
    targetAddress = targetContract.address;
    underlying = await targetContract.underlying();
    adapterParams.stake = stake.address;
    adapterParams.rewardTokens = [airdrop.address];

    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, targetAddress, underlying, ifee, adapterParams, ...(target.noncrop ? [] : target.crops ? [[airdrop.address]] : [airdrop.address])],
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
    if (!((await stake.balanceOf(deployer)).gte(ethers.utils.parseEther("1000000")))) {
      await stake.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());
    }

    log("Mint the relayer a balance of 1,000,000 STAKE");
    if (!((await stake.balanceOf(OZ_RELAYER.get(chainId))).gte(ethers.utils.parseEther("1000000")))) {
      await stake.mint(OZ_RELAYER.get(chainId), ethers.utils.parseEther("1000000")).then(tx => tx.wait());
    }
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
