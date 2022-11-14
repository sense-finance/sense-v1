const { task } = require("hardhat/config");
const data = require("./input");

const {
  SENSE_MULTISIG,
  CHAINS,
  VERIFY_CHAINS,
  BALANCER_VAULT,
  RLV_FACTORY,
  QUERY_PROCESSOR,
} = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const adapterAbi = ["function scale() public view returns (uint256)"];

const { verifyOnEtherscan, generateTokens } = require("../../hardhat.utils");

task("20221114-ownable-factory", "Deploys RLV 4626 Factory").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No multisig vault found");
  if (chainId !== CHAINS.HARDHAT && RLV_FACTORY.has(chainId)) throw Error("No RLV factory found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let {
    divider: dividerAddress,
    periphery: peripheryAddress,
    restrictedAdmin,
    rewardsRecipient,
    oracle: masterOracleAddress,
    factories,
    autoRollerFactory: autoRollerFactoryAddress,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  const balancerVault = BALANCER_VAULT.get(chainId);

  // Deploy new Space Factory (the one with getEqReserevs())
  // 1 / 10 years in seconds
  const TS = ethers.utils
    .parseEther("1")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("316224000"));
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

  const { address: spaceFactoryAddress } = await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVault, divider.address, TS, G1, G2, oracleEnabled],
    libraries: {
      QueryProcessor: QUERY_PROCESSOR.get(chainId),
    },
    log: true,
  });
  console.log(`\nSpace Factoy deployed to ${spaceFactoryAddress}`);

  console.log("\nDeploying RollerUtils");
  const { address: rollerUtilsAddress } = await deploy("RollerUtils", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("\nDeploying RollerPeriphery");
  const { address: rollerPeripheryAddress } = await deploy("RollerPeriphery", {
    from: deployer,
    args: [],
    log: true,
  });
  const autoRollerArtifact = await deployments.getArtifact("AutoRoller");

  console.log("\nDeploying an AutoRoller Factory");
  const { address } = await deploy("AutoRollerFactory", {
    from: deployer,
    args: [
      divider.address,
      balancerVault,
      periphery.address,
      rollerPeripheryAddress,
      rollerUtilsAddress,
      autoRollerArtifact.bytecode,
    ],
    log: true,
  });
  autoRollerFactoryAddress = address;
  console.log(`AutoRollerFactory deployed to ${autoRollerFactoryAddress}`);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (const factory of factories) {
    const {
      contractName: factoryContractName,
      contract,
      ifee,
      stake: stakeAddress,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
      guard,
      targets,
    } = factory;

    console.log("\n-------------------------------------------------------");
    console.log(`\nDeploy ${factoryContractName}:`);
    console.log(
      `\n - Params: ${JSON.stringify({
        ifee: ifee.toString(),
        stakeAddress,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle: masterOracleAddress,
        tilt,
        guard,
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
      console.log(`\n - Fund multisig to be able to make calls from that address`);
      await (
        await deployerSigner.sendTransaction({
          to: senseAdminMultisigAddress,
          value: ethers.utils.parseEther("1"),
        })
      ).wait();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

      console.log(`\n - Add ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();

      console.log(`\n - Set factory as trusted address of Divider so it can call setGuard()`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();

      console.log(`\n - Set new space factory on Periphery`);
      await (await periphery.setSpaceFactory(spaceFactoryAddress)).wait();

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });

      console.log("\n-------------------------------------------------------");
      console.log(`\nDeploy ownable adapters for: ${factoryContractName}`);
      console.log("\n-------------------------------------------------------");

      for (const t of targets) {
        periphery = periphery.connect(deployerSigner);

        console.log(`\n- Add target ${t.name} to the whitelist`);
        await (await factoryContract.supportTarget(t.address, true)).wait();

        console.log(`\n- Onboard target ${t.name} @ ${t.address} via ${factoryContractName}`);
        const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address, data);
        await (await periphery.deployAdapter(factoryAddress, t.address, data)).wait();
        console.log(`  ${t.name} ownable adapter address deployed to ${adapterAddress}`);

        console.log(`- Can call scale value`);
        const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
        const scale = await adptr.callStatic.scale();
        console.log(`  -> scale: ${scale.toString()}`);

        const params = await divider.adapterMeta(adapterAddress);
        console.log(`  -> adapter guard: ${params[2]}`);

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

        console.log(`\nPrepare to roll series on AutoRoller with OwnableAdapter whose target is ${t.name}`);

        console.log(`\n- Mint ${t.name} tokens...`);
        await generateTokens(t.address, deployer, deployerSigner);

        console.log(`\n- Mint stake tokens...`);
        await generateTokens(stakeAddress, deployer, deployerSigner);

        const ERC20_ABI = [
          "function approve(address spender, uint256 amount) public returns (bool)",
          "function balanceOf(address account) public view returns (uint256)",
        ];

        console.log(`\n- Approve AutoRollerFactory to pull ${t.name}...`);
        const target = new ethers.Contract(t.address, ERC20_ABI, deployerSigner);
        await target.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

        console.log(`\n- Approve AutoRollerFactory to pull stake...`);
        const stake = new ethers.Contract(stakeAddress, ERC20_ABI, deployerSigner);
        await stake.approve(autoRollerAddress, ethers.constants.MaxUint256).then(tx => tx.wait());

        // Roll into the first Series
        const autoRoller = new ethers.Contract(autoRollerAddress, autoRollerArtifact.abi, deployerSigner);
        console.log(`\n- Roll Series on AutoRoller with OwnableAdapter whose target is ${t.name}`);
        await (await autoRoller.roll()).wait();
        console.log("\n-------------------------------------------------------");
      }
    }

    console.log("\n-------------------------------------------------------");

    // Unset deployer and set multisig as trusted address
    console.log(`\n- Set multisig as trusted address of 4626CropFactory`);
    await (await factoryContract.setIsTrusted(senseAdminMultisigAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of 4626CropFactory`);
    await (await factoryContract.setIsTrusted(deployer, false)).wait();

    if (VERIFY_CHAINS.includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");

      console.log("\n1. Set factory on Periphery");
      console.log("\n2. Set factory as trusted on Divider");
      console.log(`\n3. Set new SpaceFactory on Periphery`);
      console.log("\n4. Deploy OwnableAdapter using OwnableFactory for a given target");
      console.log("\n5. Deploy AutoRoller using AutoRollerFactory using the OwnableAdapter deployed");
      console.log(`\n6. Approve AutoRollerFactory to pull taget`);
      console.log(`\n7. Approve AutoRollerFactory to pull stake`);
      console.log("\n8. For each AutoRoller, roll into first Series");
    }
  }
});
