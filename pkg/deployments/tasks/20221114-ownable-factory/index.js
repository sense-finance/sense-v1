const { task, subtask } = require("hardhat/config");
const data = require("./input");

const {
  SENSE_MULTISIG,
  CHAINS,
  VERIFY_CHAINS,
  BALANCER_VAULT,
  QUERY_PROCESSOR,
} = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const adapterAbi = ["function scale() public view returns (uint256)"];
const spaceFactoryAbi = require("./abi/SpaceFactory.json");

const {
  verifyOnEtherscan,
  generateTokens,
  setBalance,
  startPrank,
  stopPrank,
} = require("../../hardhat.utils");

task("20221114-ownable-factory", "Deploys RLV 4626 Factory").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No multisig vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  if (chainId === CHAINS.HARDHAT) {
    console.log(`\nFund multisig to be able to make calls from that address`);
    await setBalance(senseAdminMultisigAddress, ethers.utils.parseEther("1").toString());
  }

  console.log(`\nDeploying from ${deployer} on chain ${chainId}`);

  let {
    divider: dividerAddress,
    periphery: peripheryAddress,
    restrictedAdmin,
    rewardsRecipient,
    factories,
    adapters,
    autoRollerFactory: autoRollerFactoryAddress,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  const balancerVault = BALANCER_VAULT.get(chainId);

  // Deploy new Space Factory (see subtask implementation at the end)
  await hre.run("deploy-space-factory", {
    deploy,
    deployer,
    deployerSigner,
    chainId,
    balancerVault,
    divider,
    senseAdminMultisigAddress,
    periphery,
  });

  // Deploy an Auto Roller Factory
  if (!autoRollerFactoryAddress) {
    autoRollerFactoryAddress = await hre.run("deploy-auto-roller-factory", {
      deploy,
      deployer,
      deployerSigner,
      chainId,
      balancerVault,
      divider,
      senseAdminMultisigAddress,
      periphery,
    });
  }

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  console.log("\n-------------------------------------------------------");
  for (const factory of factories) {
    const {
      contractName: factoryContractName,
      contract,
      ifee,
      oracle: masterOracleAddress,
      stake: stakeAddress,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
      guard,
      targets,
    } = factory;

    console.log("\n\n---------------------------------------");
    console.log(`Deploy ${factoryContractName}`);
    console.log("---------------------------------------");
    console.log(
      `\n - Params: ${JSON.stringify({
        ifee: ifee.toString(),
        stakeAddress,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        masterOracleAddress,
        tilt,
        guard,
        autoRollerFactoryAddress,
      })}}\n`,
    );

    const factoryParams = [masterOracleAddress, stakeAddress, stakeSize, minm, maxm, ifee, mode, tilt, guard];

    const { address: factoryAddress, abi } = await deploy(factoryContractName, {
      contract: contract || factoryContractName,
      from: deployer,
      args: [divider.address, restrictedAdmin, rewardsRecipient, factoryParams, autoRollerFactoryAddress],
      log: true,
    });
    const factoryContract = new ethers.Contract(factoryAddress, abi, deployerSigner);
    console.log(`${factoryContractName} deployed to ${factoryAddress}`);

    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(factoryContractName);
    } else {
      await startPrank(senseAdminMultisigAddress);

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

      console.log(`\n - Add ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();

      console.log(`\n - Set factory as trusted address of Divider so it can call setGuard()`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();

      await stopPrank(senseAdminMultisigAddress);

      for (const t of targets) {
        console.log("\n\n---------------------------------------");
        console.log(`Deploy ${t.name} ownable adapter via ${factoryContractName}`);
        console.log("---------------------------------------");

        periphery = periphery.connect(deployerSigner);

        console.log(`\n- Add target ${t.name} to the factory supported list`);
        await (await factoryContract.supportTarget(t.address, true)).wait();

        console.log(`\n- Onboard target ${t.name} @ ${t.address} via ${factoryContractName}`);
        const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address, data);
        await (await periphery.deployAdapter(factoryAddress, t.address, data)).wait();
        console.log(`  ${t.name} ownable adapter address deployed to ${adapterAddress}`);

        console.log(`\n- Sanity check: can call scale value & guard value`);
        const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
        const scale = await adptr.callStatic.scale();
        console.log(`  * scale: ${scale.toString()}`);

        const params = await divider.adapterMeta(adapterAddress);
        console.log(`  * adapter guard: ${params[2]}`);

        console.log(
          `\n- Deploy an AutoRoller for Ownable Adapter with target ${t.name} via AutoRollerFactory`,
        );
        const autoRollerFactory = await ethers.getContract("AutoRollerFactory", deployerSigner);
        const autoRollerAddress = await autoRollerFactory.callStatic.create(
          adapterAddress,
          senseAdminMultisigAddress,
          3,
        );
        await (await autoRollerFactory.create(adapterAddress, senseAdminMultisigAddress, 3)).wait();
        console.log(`  AutoRoller deployed to ${autoRollerAddress}`);

        console.log(`\n- Prepare to roll series on AutoRoller with OwnableAdapter whose target is ${t.name}`);

        // Mint stake & target tokens
        await generateTokens(t.address, deployer, deployerSigner);
        await generateTokens(stakeAddress, deployer, deployerSigner);

        const ERC20_ABI = [
          "function approve(address spender, uint256 amount) public returns (bool)",
          "function balanceOf(address account) public view returns (uint256)",
        ];

        console.log(`  Approve AutoRoller to pull ${t.name}`);
        const target = new ethers.Contract(t.address, ERC20_ABI, deployerSigner);
        await target.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

        console.log(`  Approve AutoRoller to pull stake`);
        const stake = new ethers.Contract(stakeAddress, ERC20_ABI, deployerSigner);
        await stake.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

        // Roll into the first Series
        const autoRollerArtifact = await deployments.getArtifact("AutoRoller");
        const autoRoller = new ethers.Contract(autoRollerAddress, autoRollerArtifact.abi, deployerSigner);
        console.log(`\n- Roll Series on AutoRoller with OwnableAdapter whose target is ${t.name}`);
        await (await autoRoller.roll()).wait();
        console.log(`  Successfully rolled Series!`);

        console.log("\n-------------------------------------------------------");
      }

      // Unset deployer and set multisig as trusted address
      console.log(`\n\n- Set multisig as trusted address of ${factoryContractName}`);
      await (await factoryContract.setIsTrusted(senseAdminMultisigAddress, true)).wait();

      console.log(`- Unset deployer as trusted address of ${factoryContractName}`);
      await (await factoryContract.setIsTrusted(deployer, false)).wait();

      if (VERIFY_CHAINS.includes(chainId)) {
        console.log("\n-------------------------------------------------------");
        console.log("\nACTIONS TO BE DONE ON DEFENDER: ");

        console.log("\n1. Set factory on Periphery");
        console.log("\n2. Set factory as trusted on Divider");
        console.log(`\n3. Set new SpaceFactory on Periphery`);
        console.log("\n4. Deploy OwnableAdapter using OwnableFactory for a given target");
        console.log("\n5. Deploy AutoRoller using AutoRollerFactory using the OwnableAdapter deployed");
        console.log(`\n6. Approve AutoRoller to pull target`);
        console.log(`\n7. Approve AutoRoller to pull stake`);
        console.log("\n8. For each AutoRoller, roll into first Series");
      }
    }
  }

  console.log("\n\n-------------------------------------------------------");
  console.log("\nDeploy Adapters directly");
  console.log("\n-------------------------------------------------------");
  for (const adapter of adapters) {
    const {
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
      guard,
      target: t,
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
        guard,
      })}}\n`,
    );

    const adapterParams = [oracle, stakeAddress, stakeSize, minm, maxm, tilt, level, mode];

    const { address: adapterAddress, abi } = await deploy(adapterContractName, {
      contract: contract || adapterContractName,
      from: deployer,
      args: [divider.address, t.address, rewardsRecipient, ifee, adapterParams],
      log: true,
    });
    console.log(`${adapterContractName} deployed to ${adapterAddress}`);
    const adapterContract = new ethers.Contract(adapterAddress, abi, deployerSigner);

    // Auto Roller Factory must have adapter auth so that it can give auth to the RLV
    await (await adapterContract.setIsTrusted(autoRollerFactoryAddress, true)).wait();

    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(adapterContractName, adapterContract.address, [divider.address, t.address, rewardsRecipient, ifee, adapterParams]);
    } else {
      await startPrank(senseAdminMultisigAddress);

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

      console.log(`\n- Onboard ${t.name} adapter directly`);
      await (await periphery.onboardAdapter(adapterAddress, true)).wait();

      console.log(`\n- Verify ${t.name} adapter directly`);
      await (await periphery.verifyAdapter(adapterAddress, false)).wait();
      console.log(`  ${t.name} ownable adapter address deployed to ${adapterAddress}`);

      console.log(`\n- Set guard for ${adapterContractName}`);
      await (await divider.setGuard(adapterAddress, guard)).wait();

      await stopPrank(senseAdminMultisigAddress);

      console.log(`\n- Sanity check: can call scale value & guard value`);
      const scale = await adapterContract.callStatic.scale();
      console.log(`  * scale: ${scale.toString()}`);

      const params = await divider.adapterMeta(adapterAddress);
      console.log(`  * adapter guard: ${params[2]}`);

      console.log(
        `\n- Deploy an AutoRoller for ${adapterContractName} with target ${t.name} via AutoRollerFactory`,
      );
      const autoRollerFactory = await ethers.getContract("AutoRollerFactory", deployerSigner);
      const autoRollerAddress = await autoRollerFactory.callStatic.create(
        adapterAddress,
        senseAdminMultisigAddress,
        3,
      );
      await (await autoRollerFactory.create(adapterAddress, senseAdminMultisigAddress, 3)).wait();
      console.log(`  AutoRoller deployed to ${autoRollerAddress}`);

      console.log(`\n- Prepare to roll series on AutoRoller with OwnableAdapter whose target is ${t.name}`);

      // Mint stake & target tokens
      await generateTokens(t.address, deployer, deployerSigner);
      await generateTokens(stakeAddress, deployer, deployerSigner);

      const ERC20_ABI = [
        "function approve(address spender, uint256 amount) public returns (bool)",
        "function balanceOf(address account) public view returns (uint256)",
      ];

      console.log(`  Approve AutoRoller to pull ${t.name}`);
      const target = new ethers.Contract(t.address, ERC20_ABI, deployerSigner);
      await target.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

      console.log(`  Approve AutoRoller to pull stake`);
      const stake = new ethers.Contract(stakeAddress, ERC20_ABI, deployerSigner);
      await stake.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

      // Roll into the first Series
      const autoRollerArtifact = await deployments.getArtifact("AutoRoller");
      const autoRoller = new ethers.Contract(autoRollerAddress, autoRollerArtifact.abi, deployerSigner);
      console.log(`\n- Roll Series on AutoRoller with OwnableAdapter whose target is ${t.name}`);
      await (await autoRoller.roll()).wait();
      console.log(`  Successfully rolled Series!`);
    }

    // Unset deployer and set multisig as trusted address
    console.log(`\n\n- Set multisig as trusted address of ${adapterContractName}`);
    await (await adapterContract.setIsTrusted(senseAdminMultisigAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of ${adapterContractName}`);
    await (await adapterContract.setIsTrusted(deployer, false)).wait();

    if (VERIFY_CHAINS.includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");

      console.log("\n1. Onboard wstETH Ownable Adapter on Periphery");
      console.log("\n2. Verify wstETH Ownable Adapter on Periphery");
      console.log(`\n3. Set guard for wstETH Ownable Adapter on Divider`);
      console.log("\n4. Deploy OwnableAdapter using OwnableFactory for a given target");
      console.log("\n5. Deploy AutoRoller using AutoRollerFactory using the OwnableAdapter deployed");
      console.log(`\n6. Approve AutoRoller to pull target`);
      console.log(`\n7. Approve AutoRoller to pull stake`);
      console.log("\n8. For each AutoRoller, roll into first Series");
    }

    console.log("\n-------------------------------------------------------");
  }
});

// Deploys a new Space Factory (the one with getEqReserevs())
subtask("deploy-space-factory", "Deploys a new Space Factory").setAction(async args => {
  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy new Space Factory");
  console.log("\n-------------------------------------------------------");

  let {
    deploy,
    deployer,
    deployerSigner,
    chainId,
    balancerVault,
    divider,
    senseAdminMultisigAddress,
    periphery,
  } = args;

  const { oldSpaceFactory: oldSpaceFactoryAddress } = data[chainId] || data[CHAINS.MAINNET];
  const oldSpaceFactory = new ethers.Contract(oldSpaceFactoryAddress, spaceFactoryAbi, deployerSigner);

  // 1 / 12 years in seconds
  const TS = "2640612622";
  // 5% of implied yield for selling Target
  const G1 = ethers.utils
    .parseEther("950")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("1000"));
  // 5% of implied yield for selling PTs
  const G2 = ethers.utils
    .parseEther("1000")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("950"));
  const oracleEnabled = true;
  const balancerFeesEnabled = false;

  await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVault, divider.address, TS, G1, G2, oracleEnabled, balancerFeesEnabled],
    libraries: {
      QueryProcessor: QUERY_PROCESSOR.get(chainId),
    },
    log: true,
  });
  const spaceFactory = await ethers.getContract("SpaceFactory", deployerSigner);
  console.log(`\nSpace Factory deployed to ${spaceFactory.address}`);

  const sponsoredSeries = (
    await divider.queryFilter(divider.filters.SeriesInitialized(null, null, null, null, null, null))
  ).map(series => ({ adapter: series.args.adapter, maturity: series.args.maturity.toString() }));

  console.log(`\nSetting ${sponsoredSeries.length} pools...`);
  let i = 1;
  for (let { adapter, maturity } of sponsoredSeries) {
    const pool = await oldSpaceFactory.pools(adapter, maturity);
    console.log(`- Pool ${i}`)
    if ((await spaceFactory.pools(adapter, maturity)) === ethers.constants.AddressZero) {
      console.log(
        `\n- Adding ${adapter} ${maturity} Series with pool ${pool} to new Space Factory pools mapping`,
      );
      await spaceFactory.setPool(adapter, maturity, pool, { gasLimit: 55000, gasPrice: 16000000000 }).then(t => t.wait());
      console.log(`  Added pool ${await spaceFactory.pools(adapter, maturity)}`);
    }
    i++;
  }

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(
      "SpaceFactory", 
      spaceFactory.address, 
      [balancerVault, divider.address, TS, G1, G2, oracleEnabled, balancerFeesEnabled],
      { QueryProcessor: QUERY_PROCESSOR.get(chainId) }
    );
  } else {
    await startPrank(senseAdminMultisigAddress);

    const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
    divider = divider.connect(multisigSigner);
    periphery = periphery.connect(multisigSigner);

    console.log(`\n- Set new space factory on Periphery`);
    await (await periphery.setSpaceFactory(spaceFactory.address)).wait();

    await stopPrank(senseAdminMultisigAddress);
  }

  console.log(`\n\n- Set multisig as trusted address of SpaceFactory`);
  await (await spaceFactory.setIsTrusted(senseAdminMultisigAddress, true)).wait();

  console.log(`\n- Unset deployer as trusted address of SpaceFactory`);
  await (await spaceFactory.setIsTrusted(deployer, false)).wait();
  console.log("\n\n");
});

// Deploys a new Space Factory (the one with getEqReserevs())
subtask("deploy-auto-roller-factory", "Deploys a new Space Factory").setAction(async args => {
  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Auto Roller Factory");
  console.log("\n-------------------------------------------------------");

  let {
    deploy,
    deployer,
    deployerSigner,
    chainId,
    balancerVault,
    divider,
    senseAdminMultisigAddress,
    periphery,
  } = args;

  console.log("\nDeploying RollerUtils");
  await deploy("RollerUtils", {
    from: deployer,
    args: [divider.address],
    log: true,
  });
  const rollerUtils = await ethers.getContract("RollerUtils", deployerSigner);
  console.log(`\nRollerUtils deployed to ${rollerUtils.address}`);

  console.log("\nDeploying RollerPeriphery");
  await deploy("RollerPeriphery", {
    from: deployer,
    args: [],
    log: true,
  });
  const rollerPeriphery = await ethers.getContract("RollerPeriphery", deployerSigner);
  console.log(`\nRollerPeriphery deployed to ${rollerPeriphery.address}`);

  console.log("\nDeploying an AutoRoller Factory");
  await deploy("AutoRollerFactory", {
    from: deployer,
    args: [
      divider.address,
      balancerVault,
      periphery.address,
      rollerPeriphery.address,
      rollerUtils.address
    ],
    log: true,
  });
  const autoRollerFactory = await ethers.getContract("AutoRollerFactory", deployerSigner);
  console.log(`\nAutoRollerFactory deployed to ${autoRollerFactory.address}`);

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");

    await verifyOnEtherscan("AutoRollerFactory", autoRollerFactory.address, [
      divider.address,
      balancerVault,
      periphery.address,
      rollerPeriphery.address,
      rollerUtils.address
    ]);
    await verifyOnEtherscan("RollerPeriphery", rollerPeriphery.address, []);
  }

  console.log(
    `\n- Set AutoRollerFactory as trusted address on RollerPeriphery to be able to use the approve() function`,
  );
  await (await rollerPeriphery.setIsTrusted(autoRollerFactory.address, true)).wait();

  console.log(`\n- Set multisig as trusted address of AutoRollerFactory`);
  await (await autoRollerFactory.setIsTrusted(senseAdminMultisigAddress, true)).wait();

  console.log(`\n- Unset deployer as trusted address of AutoRollerFactory`);
  await (await autoRollerFactory.setIsTrusted(deployer, false)).wait();

  console.log(`\n- Set multisig as trusted address of RollerPeriphery`);
  await (await rollerPeriphery.setIsTrusted(senseAdminMultisigAddress, true)).wait();

  console.log(`\n- Unset deployer as trusted address of RollerPeriphery`);
  await (await rollerPeriphery.setIsTrusted(deployer, false)).wait();

  console.log("\n\n");
  return autoRollerFactory.address;
});
