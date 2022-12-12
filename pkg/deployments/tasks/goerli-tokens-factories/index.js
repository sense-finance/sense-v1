const { task, subtask } = require("hardhat/config");
const input = require("./input");

const { CHAINS, OZ_RELAYER } = require("../../hardhat.addresses");
const adapterAbi = ["function scale() public view returns (uint256)"];

const { verifyOnEtherscan, getRelayerSigner, trust, approve } = require("../../hardhat.utils");

const deployToken = async (token, underlying, deploy, signer) => {
  let deployedData;
  let { name, symbol, decimals, address, contract, contractName } = token;
  console.log(`\nDeploy ${contract} ${symbol}`);
  let args = [...(underlying ? [underlying] : []), name, symbol, decimals];
  if (!address) {
    await deploy(contractName, {
      contract,
      from: signer.address,
      args,
      log: true,
    });
    console.log(`\n${symbol} deployed to ${deployedData.address}`);
    await verifyOnEtherscan(contract, address, args);
  } else {
    console.log(`\nUsing ${symbol} deployed to ${address}`);
  }
  return await ethers.getContractAt(contract, address, signer);
};

task(
  "goerli-tokens-factories",
  "Deploys underlyings, targets, stake, reward, non-crop and erc4626 Factories",
).setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);
  const relayerSigner = await getRelayerSigner();

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let {
    divider: dividerAddress,
    periphery: peripheryAddress,
    restrictedAdmin,
    rewardsRecipient,
    oracle: masterOracleAddress,
    balancerVault,
    factories,
    adapters,
    data,
    rollerUtils: rollerUtilsAddress,
    rollerPeriphery: rollerPeripheryAddress,
    rlvFactory: rlvFactoryAddress,
  } = input[chainId];

  let divider = await ethers.getContractAt("Divider", dividerAddress, deployerSigner);
  let periphery = await ethers.getContractAt("Periphery", peripheryAddress, deployerSigner);

  // Deploy all tokens
  await hre.run("goerli-deploy-tokens", {
    deploy,
    deployerSigner,
    data,
  });

  // Deploy an Auto Roller Factory
  let rlvFactory = await hre.run("deploy-auto-roller-factory", {
    deploy,
    deployer,
    deployerSigner,
    balancerVault,
    divider,
    periphery,
    rollerUtilsAddress,
    rollerPeripheryAddress,
    rlvFactoryAddress,
  });

  // Deploy factories and adapters via those factories
  await hre.run("goerli-deploy-factories", {
    deploy,
    deployer,
    deployerSigner,
    relayerSigner,
    factories,
    rlvFactory,
    masterOracleAddress,
    rewardsRecipient,
    restrictedAdmin,
    periphery,
    divider,
    rlvFactoryAddress,
  });

  // Deploy adapters directly (without a factory)
  await hre.run("goerli-deploy-adapters", {
    deploy,
    deployer,
    deployerSigner,
    adapters,
    rlvFactory,
    rewardsRecipient,
    restrictedAdmin,
    periphery,
  });
});

task("goerli-deploy-factories", "Deploy factories and adapters via those factories").setAction(async args => {
  let {
    deploy,
    deployer,
    deployerSigner,
    relayerSigner,
    factories,
    rlvFactory,
    masterOracleAddress,
    rewardsRecipient,
    periphery,
    divider,
    restrictedAdmin,
    rlvFactoryAddress,
  } = args;

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (const factory of factories) {
    let {
      address: factoryAddress,
      contractName: factoryContractName,
      contract,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
      guard,
      targets,
      reward,
      isOwnable,
      maturities,
    } = factory;

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy ${contract || factoryContractName}`);
    console.log("-------------------------------------------------------\n");
    console.log(
      `Params: ${JSON.stringify({
        address: factoryAddress,
        ifee: ifee.toString(),
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle: masterOracleAddress,
        tilt,
        guard,
        reward,
      })}}\n`,
    );

    if (!factoryAddress) {
      const factoryParams = [masterOracleAddress, stake, stakeSize, minm, maxm, ifee, mode, tilt, guard];
      const { address } = await deploy(factoryContractName, {
        contract: contract || factoryContractName,
        from: deployer,
        args: [
          divider.address,
          restrictedAdmin,
          rewardsRecipient,
          factoryParams,
          ...(reward ? [reward.address] : []),
          ...(rlvFactoryAddress ? [rlvFactoryAddress] : []),
        ],
        log: true,
      });
      console.log(`${factoryContractName} deployed to ${address}`);
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(factoryContractName);
      factoryAddress = address;
    } else {
      console.log(`\nUsing ${factoryContractName} deployed to ${factoryAddress}`);
    }
    const factoryContract = await ethers.getContractAt(contract, factoryAddress, deployerSigner);

    if (!(await periphery.factories(factoryAddress))) {
      console.log(`\n - Add ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();
    }

    console.log(`\n - Set factory as trusted address of Divider so it can call setGuard()`);
    await trust(divider, OZ_RELAYER.get(CHAINS.GOERLI));

    const stakeContract = await ethers.getContractAt("AuthdMockToken", stake, relayerSigner);

    console.log(`\n - Approve Periphery to pull stake...`);
    await approve(stakeContract, deployer, periphery.address);

    if ((await stakeContract.balanceOf(OZ_RELAYER.get(CHAINS.GOERLI))).eq(0)) {
      console.log(` - Mint stake tokens to relayer...`);
      await stakeContract
        .mint(OZ_RELAYER.get(CHAINS.GOERLI), ethers.utils.parseEther("1"))
        .then(tx => tx.wait());
    }

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy adapters for: ${factoryContractName}`);
    console.log("-------------------------------------------------------");

    for (const t of targets) {
      if (!(await factoryContract.targets(t.address))) {
        console.log(`\n- Add target ${t.name} to the whitelist`);
        await (await factoryContract.supportTarget(t.address, true)).wait();
      }

      let adapterAddress = t.adapter;
      if (!adapterAddress) {
        console.log(`\n- Onboard target ${t.symbol} @ ${t.address} via ${factoryContractName}`);
        const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
        await (await periphery.deployAdapter(factoryAddress, t.address, data)).wait();
        console.log(`- ${t.symbol} adapter address: ${adapterAddress}`);
      } else {
        console.log(`\n- Using ${t.symbol} adapter deployed to ${adapterAddress}`);
      }

      console.log(`\n- Sanity check: can call scale value & guard value`);
      const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
      const params = await divider.adapterMeta(adapterAddress);
      const scale = await adptr.callStatic.scale();
      console.log(`  * scale: ${scale.toString()}`);
      console.log(`  * adapter guard: ${params[2]}`);

      // Create RLV (see subtask implementation at the end)
      if (isOwnable) {
        await hre.run("goerli-rlv", {
          deploy,
          deployer,
          deployerSigner,
          relayerSigner,
          rlvFactory,
          periphery,
          adapterAddress,
          t,
        });
      } else {
        periphery = periphery.connect(relayerSigner);
        const target = await ethers.getContractAt("AuthdMockTarget", t.address, relayerSigner);

        console.log(`\n- Approve Periphery to pull target...`);
        await approve(target, deployer, periphery.address);

        if ((await target.balanceOf(OZ_RELAYER.get(CHAINS.GOERLI))).eq(0)) {
          console.log(`- Mint target tokens to relayer...`);
          await target
            .mint(OZ_RELAYER.get(CHAINS.GOERLI), ethers.utils.parseEther("1"))
            .then(tx => tx.wait());
        }

        // sponsor Series
        for (let m of maturities) {
          console.log(`  * Sponsor Series for ${t.symbol} @ ${adapterAddress} with maturity (${m.unix()})`);
          await periphery.callStatic.sponsorSeries(adapterAddress, m.unix(), false);
        }
      }
      console.log("\n-------------------------------------------------------");
    }

    console.log("\n-------------------------------------------------------");
  }
});

task("goerli-deploy-adapters", "Deploy adapters without a factory").setAction(async args => {
  let {
    deploy,
    deployer,
    deployerSigner,
    relayerSigner,
    adapters,
    rlvFactory,
    rewardsRecipient,
    periphery,
    balancerVault,
    divider,
  } = args;

  console.log("\n\n-------------------------------------------------------");
  console.log("\nDeploy Adapters directly");
  console.log("\n-------------------------------------------------------");

  for (const adapter of adapters) {
    let {
      address: adapterAddress,
      contractName: adapterContractName,
      contract,
      ifee,
      oracle,
      stake: stakeAddress,
      stakeSize,
      minm,
      maxm,
      tilt,
      level,
      mode,
      target: t,
      isOwnable,
      maturities,
    } = adapter;

    console.log("\n\n---------------------------------------");
    console.log(`Deploy ${adapterContractName}`);
    console.log("---------------------------------------");
    console.log(
      `\n - Params: ${JSON.stringify({
        t,
        ifee: ifee.toString(),
        stakeAddress,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle,
        tilt,
      })}}\n`,
    );

    const adapterParams = [oracle, stakeAddress, stakeSize, minm, maxm, tilt, level, mode];
    if (!adapterAddress) {
      const target = await ethers.getContractAt("AuthdMockTarget", t.address, deployerSigner);
      const { address: adapterAddress } = await deploy(adapterContractName, {
        contract: contract || adapterContractName,
        from: deployer,
        args: [divider.address, t.address, await target.underlying(), adapterParams],
        log: true,
      });
      console.log(`${adapterContractName} deployed to ${adapterAddress}`);

      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(contract, adapterAddress, [
        divider.address,
        t.address,
        rewardsRecipient,
        adapterParams,
      ]);
    } else {
      console.log(`\nUsing ${adapterContractName} deployed to ${adapterAddress}`);
    }

    // Auto Roller Factory must have adapter auth so that it can give auth to the RLV
    const adapterContract = await ethers.getContractAt(adapterContractName, adapterAddress, deployerSigner);
    await trust(adapterContract, rlvFactory);

    const params = await divider.adapterMeta(adapterAddress);
    if (!params[1]) {
      console.log(`\n- Onboard ${t.name} adapter directly`);
      await (await periphery.onboardAdapter(adapterAddress, true)).wait();

      console.log(`\n- Verify ${t.name} adapter directly`);
      await (await periphery.verifyAdapter(adapterAddress, false)).wait();
      console.log(`  ${t.name} ownable adapter address deployed to ${adapterAddress}`);
    }

    if (params[2].eq(0)) {
      console.log(`\n- Set guard for ${adapterContractName}`);
      await (await divider.setGuard(adapterAddress, ethers.constants.MaxUint256)).wait();
    }

    console.log(`\n- Sanity check: can call scale value & guard value`);
    const scale = await adapterContract.callStatic.scale();
    console.log(`  * scale: ${scale.toString()}`);
    console.log(`  * adapter guard: ${params[2]}`);

    // Create RLV (see subtask implementation at the end)
    if (isOwnable) {
      await hre.run("goerli-rlv", {
        deploy,
        deployer,
        deployerSigner,
        relayerSigner,
        rlvFactory,
        periphery,
        adapterAddress,
        stakeAddress,
        balancerVault,
        t,
      });
    } else {
      // sponsor Series
      for (let m of maturities) {
        console.log(
          `  * Sponsor Series for ${await adapterContract.symbol()} @ ${balancerVault} with maturity ${m.format(
            "ll",
          )} (${m.unix()})`,
        );
        await periphery.callStatic.sponsorSeries(adapterAddress, m.unix(), false);
        await (await periphery.sponsorSeries(adapterAddress, m.unix(), false)).wait();
      }
    }

    console.log("\n-------------------------------------------------------");
  }
});

task("goerli-deploy-tokens", "Deploy tokens").setAction(async args => {
  let { deploy, deployerSigner, data } = args;

  let deployedTokens = [];
  console.log("\n-------------------------------------------------------");
  const { tokens, stake, reward } = data;
  console.log("\nDeploy Tokens");
  for (const token of tokens) {
    for (const type in token) {
      console.log("\n-------------------------------------------------------");
      if (!token.underlying) throw Error("Missing underlying");
      let underlying;
      if (["target", "target4626"].includes(type)) {
        underlying = token.underlying?.address || deployedTokens[token.underlying.symbol].address;
      }
      deployedTokens[token[type].symbol] = await deployToken(token[type], underlying, deploy, deployerSigner);
      // ERC4626 tokens are not mintable, we would need to mint underlying and then deposit
      if (type !== "target4626") {
        console.log(`\n - Set relayer as trusted of ${token[type].symbol} so it can mint tokens`);
        await trust(deployedTokens[token[type].symbol], OZ_RELAYER.get(CHAINS.GOERLI));
      }
    }
  }
  deployedTokens[stake.symbol] = await deployToken(stake, null, deploy, deployerSigner);
  console.log(`\n - Set relayer as trusted of ${stake.symbol} so it can mint tokens`);
  await trust(deployedTokens[stake.symbol], OZ_RELAYER.get(CHAINS.GOERLI));
  deployedTokens[reward.symbol] = await deployToken(reward, null, deploy, deployerSigner);
  console.log(`\n - Set relayer as trusted of ${stake.symbol} so it can mint tokens`);
  await trust(deployedTokens[stake.symbol], OZ_RELAYER.get(CHAINS.GOERLI));

  console.log("\n\n");
  return deployedTokens;
});

task("goerli-rlv", "Create RLV").setAction(async args => {
  let { deployer, relayerSigner, rlvFactory, periphery, adapterAddress, t, balancerVault, stakeAddress } =
    args;

  // create AutoRoller from OZ relayer
  console.log(`\n- Deploy an AutoRoller for Ownable Adapter with target ${t.name} via AutoRollerFactory`);
  const autoRollerFactory = await ethers.getContractAt("AutoRollerFactory", rlvFactory, relayerSigner);
  const autoRollerAddress = (await autoRollerFactory.rollers(adapterAddress, 0)).catch(() =>
    console.log(`  ${adapterAddress} does not have an RLV. Creating one...`),
  );
  if (!autoRollerAddress) {
    const autoRollerAddress = await autoRollerFactory.callStatic.create(
      adapterAddress,
      deployer, // reward recipient
      1,
    );
    await (await autoRollerFactory.create(adapterAddress, deployer, 3)).wait();
    console.log(`  AutoRoller deployed to ${autoRollerAddress}`);

    const constructorArgs = [
      t.address,
      await periphery.divider(),
      periphery.address,
      await periphery.spaceFactory(),
      await balancerVault,
      adapterAddress,
      await autoRollerFactory.utils(),
      deployer,
    ];
    await verifyOnEtherscan("@auto-roller/src/AutoRoller.sol:AutoRoller", autoRollerAddress, constructorArgs);
  } else {
    console.log(`  Using AutoRoller deployed to ${autoRollerAddress}`);
  }

  console.log(`\n- Prepare to roll series on AutoRoller with OwnableAdapter whose target is ${t.name}`);

  // Approvals and minting of stake
  const stakeContract = await ethers.getContractAt("AuthdMockToken", stakeAddress, relayerSigner);

  console.log(`\n- Approve Periphery to pull stake from relayer...`);
  await approve(stakeContract, OZ_RELAYER.get(CHAINS.GOERLI), periphery.address);

  console.log(`  Approve AutoRoller to pull stake`);
  await approve(stakeContract, OZ_RELAYER.get(CHAINS.GOERLI), autoRollerAddress);

  if ((await stakeContract.balanceOf(OZ_RELAYER.get(CHAINS.GOERLI))).eq(0)) {
    console.log(`- Mint stake tokens to relayer...`);
    await stakeContract
      .mint(OZ_RELAYER.get(CHAINS.GOERLI), ethers.utils.parseEther("1"))
      .then(tx => tx.wait());
  }

  // Approvals and minting of target
  const target = await ethers.getContractAt("AuthdMockTarget", t.address, relayerSigner);

  console.log(`  Approve AutoRoller to pull ${t.name}`);
  await approve(target, OZ_RELAYER.get(CHAINS.GOERLI), autoRollerAddress);

  if ((await target.balanceOf(OZ_RELAYER.get(CHAINS.GOERLI))).eq(0)) {
    console.log(`- Mint target tokens to relayer...`);
    await target.mint(OZ_RELAYER.get(CHAINS.GOERLI), ethers.utils.parseEther("1")).then(tx => tx.wait());
  }

  // Roll into the first Series
  const autoRoller = await ethers.getContractAt("AutoRoller", autoRollerAddress, relayerSigner);
  console.log(`\n- Roll Series on AutoRoller with OwnableAdapter whose target is ${t.name}`);
  await autoRoller.callStatic.roll();
  console.log(`  Successfully rolled Series!`);
  console.log("\n\n");
});

// Deploys a new RLV Factory
subtask("deploy-auto-roller-factory", "Deploys a new Auto Roller Factory").setAction(async args => {
  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Auto Roller Factory");
  console.log("\n-------------------------------------------------------");

  let {
    deploy,
    deployer,
    deployerSigner,
    balancerVault,
    divider,
    periphery,
    rollerUtilsAddress,
    rollerPeripheryAddress,
    rlvFactoryAddress,
  } = args;

  let rollerUtils, rollerPeriphery, rlvFactory;

  if (!rollerUtilsAddress) {
    console.log("\nDeploying RollerUtils");
    await deploy("RollerUtils", {
      from: deployer,
      args: [divider.address],
      log: true,
    });
    rollerUtils = await ethers.getContract("RollerUtils", deployerSigner);
    console.log(`\nRollerUtils deployed to ${rollerUtils.address}`);
    await verifyOnEtherscan("@auto-roller/src/AutoRoller.sol:RollerUtils", rollerUtils.address, [
      divider.address,
    ]);
  } else {
    rollerUtils = await ethers.getContractAt("RollerUtils", rollerUtilsAddress, deployerSigner);
    console.log(`\nUsing RollerUtils at ${rollerUtils.address}`);
  }

  if (!rollerPeripheryAddress) {
    console.log("\nDeploying RollerPeriphery");
    await deploy("RollerPeriphery", {
      from: deployer,
      args: [],
      log: true,
    });
    rollerPeriphery = await ethers.getContract("RollerPeriphery", deployerSigner);
    console.log(`\nRollerPeriphery deployed to ${rollerPeriphery.address}`);
    await verifyOnEtherscan(
      "@auto-roller/src/RollerPeriphery.sol:RollerPeriphery",
      rollerPeriphery.address,
      [],
    );
  } else {
    rollerPeriphery = await ethers.getContractAt("RollerPeriphery", rollerPeripheryAddress, deployerSigner);
    console.log(`\nUsing RollerPeriphery at ${rollerPeriphery.address}`);
  }

  if (!rlvFactoryAddress) {
    console.log("\nDeploying an AutoRoller Factory");
    await deploy("AutoRollerFactory", {
      from: deployer,
      args: [divider.address, balancerVault, periphery.address, rollerPeriphery.address, rollerUtils.address],
      log: true,
    });
    rlvFactory = await ethers.getContract("AutoRollerFactory", deployerSigner);
    console.log(`\nAutoRollerFactory deployed to ${rlvFactory.address}`);
    await verifyOnEtherscan("@auto-roller/src/AutoRollerFactory.sol:AutoRollerFactory", rlvFactory.address, [
      divider.address,
      balancerVault,
      periphery.address,
      rollerPeriphery.address,
      rollerUtils.address,
    ]);
  } else {
    rlvFactory = await ethers.getContractAt("AutoRollerFactory", rlvFactoryAddress, deployerSigner);
    console.log(`\nUsing AutoRollerFactory at ${rlvFactory.address}`);
  }

  console.log(
    `\n- Set AutoRollerFactory as trusted address on RollerPeriphery to be able to use the approve() function`,
  );
  await trust(rollerPeriphery, rlvFactory.address);

  console.log("\n\n");
  return rlvFactory.address;
});
