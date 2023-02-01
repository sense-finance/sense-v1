const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS, VERIFY_CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const adapterAbi = require("./abi/OwnableERC4626CropAdapter.json");
const rlvFactoryAbi = require("./abi/AutoRollerFactory.json");
const rlvAbi = require("./abi/AutoRoller.json");

const {
  verifyOnEtherscan,
  setBalance,
  stopPrank,
  startPrank,
  generateTokens,
} = require("../../hardhat.utils");

task(
  "20230102-ownable-erc4626-crop-factory",
  "Deploys an Ownable 4626 Crop Factory & tests deploying an RLV for sanFRAX_EUR and rolling",
).setAction(async (_, { ethers }) => {
  const _deployAdapter = async (periphery, divider, factory, target) => {
    const { name, address } = target;
    console.log("\n-------------------------------------------------------");
    console.log("Deploy Ownable Adapter for %s", name);
    console.log("-------------------------------------------------------\n");

    // periphery = periphery.connect(deployerSigner);
    if (chainId === CHAINS.HARDHAT) startPrank(senseAdminMultisigAddress);

    console.log(`- Add target ${name} to the whitelist`);
    await (await factory.supportTarget(address, true)).wait();

    console.log(`- Onboard target ${name} @ ${address} via factory`);
    const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
    const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, address, data);
    await (await periphery.deployAdapter(factoryAddress, address, data)).wait();
    console.log(`- ${name} adapter address: ${adapterAddress}`);

    console.log(`- Can call scale value`);
    const adapter = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
    const scale = await adapter.callStatic.scale();
    console.log(`  -> scale: ${scale.toString()}`);

    const params = await await divider.adapterMeta(adapterAddress);
    console.log(`  -> adapter guard: ${params[2]}`);

    if (chainId === CHAINS.HARDHAT) stopPrank(senseAdminMultisigAddress);

    return adapter;
  };

  const _roll = async (target, stake, stakeSize, rlv) => {
    // approve RLV to pull target
    await (await target.approve(rlv.address, ethers.utils.parseEther("2"))).wait();

    // approve RLV to pull stake
    await (await stake.approve(rlv.address, stakeSize)).wait();

    // load wallet
    await generateTokens(stake.address, deployer, stakeSize, deployerSigner);
    await generateTokens(target.address, deployer, ethers.utils.parseEther("10"), deployerSigner);

    // roll 1st series
    await (await rlv.roll()).wait();
    console.log("- First series sucessfully rolled!");

    // check we can deposit
    await (await rlv.deposit(ethers.utils.parseEther("1"), deployer)).wait(); // deposit 1 target
    console.log("- 1 target sucessfully deposited!");
  };

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);
  const {
    divider: dividerAddress,
    periphery: peripheryAddress,
    restrictedAdmin,
    rewardsRecipient,
    oracle: masterOracleAddress,
    factoryArgs,
    rlvFactory: rlvFactoryAddress,
    reward,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  let rlvFactory = new ethers.Contract(rlvFactoryAddress, rlvFactoryAbi, deployerSigner);

  console.log("-------------------------------------------------------");
  console.log("Deploy Ownable ERC4626 Crop Factory");
  console.log("-------------------------------------------------------");

  const { contractName, contract, ifee, stake, stakeSize, minm, maxm, mode, tilt, guard, target } =
    factoryArgs;

  console.log(
    `Params: ${JSON.stringify({
      ifee: ifee.toString(),
      stake,
      stakeSize: stakeSize.toString(),
      minm,
      maxm,
      mode,
      oracle: masterOracleAddress,
      tilt,
      guard,
    })}}\n`,
  );

  const factoryParams = [masterOracleAddress, stake, stakeSize, minm, maxm, ifee, mode, tilt, guard];

  const { address: factoryAddress, abi } = await deploy(contractName, {
    contract: contract || contractName,
    from: deployer,
    args: [divider.address, restrictedAdmin, rewardsRecipient, factoryParams, rlvFactoryAddress],
    log: true,
    // gasPrice: 28000000000,
  });
  let factory = new ethers.Contract(factoryAddress, abi, deployerSigner);

  console.log(`${contractName} deployed to ${factoryAddress}`);

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(contractName);
  }

  // Mainnet would require multisig to make these calls
  if (chainId === CHAINS.HARDHAT) {
    console.log(`- Fund multisig to be able to make calls from that address`);
    await setBalance(senseAdminMultisigAddress, ethers.utils.parseEther("1").toString());
  }

  if (chainId !== CHAINS.MAINNET) {
    if (chainId === CHAINS.HARDHAT) {
      startPrank(senseAdminMultisigAddress);
      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);
    }

    console.log(`- Add ${contractName} support to Periphery`);
    await (await periphery.setFactory(factoryAddress, true)).wait();

    console.log(`- Set factory as trusted address of Divider so it can call setGuard()`);
    await (await divider.setIsTrusted(factoryAddress, true)).wait();

    if (chainId === CHAINS.HARDHAT) {
      stopPrank(senseAdminMultisigAddress);
      divider = divider.connect(deployerSigner);
      periphery = periphery.connect(deployerSigner);
    }
  }

  console.log("\nDeploy sanFRAX_EUR_Wrapper rewards claimer");
  const { address: claimerAddress } = await deploy("PingPongClaimer", {
    from: deployer,
    args: [],
    log: true,
    // gasPrice: 28000000000,
  });
  console.log(`- PingPongClaimer deployed to ${claimerAddress}`);
  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan("PingPongClaimer");
  }

  console.log("\nDeploy rewards distributor");
  const { address: rdAddress } = await deploy("RewardsDistributor", {
    from: deployer,
    args: [reward],
    log: true,
    // gasPrice: 28000000000,
  });
  console.log("- Rewards distributor deployed @ %s", rdAddress);

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan("RewardsDistributor");
  }

  if (chainId !== CHAINS.MAINNET) {
    const adapter = await _deployAdapter(periphery, divider, factory, target);
    // set claimer
    // TODO: for Mainnet, this will have to be done after we have deployed the adapter (via Defender)
    console.log("- Set deployer address as a trusted on adapter");
    await (await factory.setAdapterTrusted(adapter.address, deployer, true)).wait();
    console.log("- Set claimer to adapter");
    await (await adapter.setClaimer(claimerAddress)).wait();
    // create RLV
    console.log("\n-------------------------------------------------------");
    console.log("Create RLV for %s", await adapter.name());
    console.log("-------------------------------------------------------\n");
    const rlvAddress = await rlvFactory.callStatic.create(adapter.address, rdAddress, 3);
    await (await rlvFactory.create(adapter.address, rdAddress, 3)).wait();
    const rlv = new ethers.Contract(rlvAddress, rlvAbi, deployerSigner);
    console.log("- RLV %s deployed @ %s", await rlv.name(), rlvAddress);
    // roll first series
    const ERC20_ABI = ["function approve(address spender, uint256 amount) public returns (bool)"];
    const stakeContract = new ethers.Contract(stake, ERC20_ABI, deployerSigner);
    const targetContract = new ethers.Contract(target.address, ERC20_ABI, deployerSigner);
    await _roll(targetContract, stakeContract, stakeSize, rlv);
  }

  console.log("\n-------------------------------------------------------");

  if (deployer.toUpperCase() !== senseAdminMultisigAddress.toUpperCase()) {
    // Unset deployer and set multisig as trusted address
    console.log(`\n- Set multisig as trusted address of Factory`);
    await (await factory.setIsTrusted(senseAdminMultisigAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of Factory`);
    await (await factory.setIsTrusted(deployer, false)).wait();

    console.log("- Unset deployer as trusted address of Factory");
    await (await distributor.transferOwnership(senseAdminMultisigAddress)).wait();
  }

  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("-------------------------------------------------------");
    console.log("ACTIONS TO BE DONE ON DEFENDER: ");
    console.log("1. Set factory on Periphery (multisig)");
    console.log("2. Set factory as trusted on Divider (multisig)");
    console.log("3. Deploy ownable adapter on Periphery using factory (relayer)");
    console.log("4. Go back to script, and deploy the claimer");
    console.log("5. Set claimer to adapter (multisig)");
    console.log("6. Create RLV using AutoRollerFactory and the rewards distributor address (relayer)");
    console.log("7. Roll first series (relayer)");
  }
});
