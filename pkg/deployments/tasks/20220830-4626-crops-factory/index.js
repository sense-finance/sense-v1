const { task } = require("hardhat/config");
const data = require("./input");

const {
  SENSE_MULTISIG,
  CHAINS,
  MSTABLE_RARI_ORACLE,
  MUSD_TOKEN,
  IMUSD_TOKEN,
  VERIFY_CHAINS,
} = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const oracleAbi = require("./abi/MasterPriceOracle.json");
const erc4626FactoryAbi = require("./abi/ERC4626Factory.json");
const adapterAbi = ["function scale() public view returns (uint256)"];

const { verifyOnEtherscan, generateStakeTokens } = require("../../hardhat.utils");

task(
  "20220830-4626-crops-factory",
  "Deploys 4626 Factory. Also fixes bug in Chainlink Oracle.",
).setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  const {
    divider: dividerAddress,
    periphery: peripheryAddress,
    oracle: masterOracleAddress,
    erc4626Factory: erc4626FactoryAddress,
    restrictedAdmin,
    rewardsRecipient,
    factories,
    maxSecondsBeforePriceIsStale,
  } = data[chainId] || data[CHAINS.MAINNET];
  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  let masterOracle = new ethers.Contract(masterOracleAddress, oracleAbi, deployerSigner);
  let erc4626Factory = new ethers.Contract(erc4626FactoryAddress, erc4626FactoryAbi, deployerSigner);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Sense Chainlink Price Oracle");
  const { address: chainlinkOracleAddress } = await deploy("ChainlinkPriceOracle", {
    from: deployer,
    args: [maxSecondsBeforePriceIsStale],
    log: true,
  });
  console.log(`ChainlinkPriceOracle deployed to ${chainlinkOracleAddress}`);
  // if mainnet or goerli, verify on etherscan
  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(chainlinkOracleAddress, [maxSecondsBeforePriceIsStale]);
  }

  console.log(`\nChange ChainlinkPriceOracle on Sense Master Oracle`);
  // Since we forgot to unset the deployer address as trusted and trusting the multisig
  // we can do this from the deployer address now
  await (await masterOracle.setSenseChainlinkPriceOracle(chainlinkOracleAddress)).wait();
  console.log(`New ChainlinkPriceOracle address: ${await masterOracle.senseChainlinkPriceOracle()}`);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (const factory of factories) {
    const {
      contractName: factoryContractName,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
      guard,
      targets,
    } = factory;

    console.log(
      `\nDeploy ${factoryContractName} with params ${JSON.stringify({
        ifee: ifee.toString(),
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle: masterOracleAddress,
        tilt,
        guard,
      })}}`,
    );
    const factoryParams = [masterOracleAddress, stake, stakeSize, minm, maxm, ifee, mode, tilt, guard];
    const { address: factoryAddress, abi } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, restrictedAdmin, rewardsRecipient, factoryParams],
      log: true,
    });
    const factoryContract = new ethers.Contract(factoryAddress, abi, deployerSigner);

    console.log(`${factoryContractName} deployed to ${factoryAddress}`);

    // if not hardhat fork, we try verifying on etherscan
    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(factoryAddress, [divider.address, factoryParams]);
    } else {
      console.log("\nAdd Rari's mStable oracle to Master Price Oracle");
      await (
        await masterOracle.add(
          [MUSD_TOKEN.get(chainId), IMUSD_TOKEN.get(chainId)],
          [MSTABLE_RARI_ORACLE.get(chainId), MSTABLE_RARI_ORACLE.get(chainId)],
        )
      ).wait();

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

      // fund multisig
      console.log(`\nFund multisig to be able to make calls from that address`);
      await (
        await deployerSigner.sendTransaction({
          to: senseAdminMultisigAddress,
          value: ethers.utils.parseEther("1"),
        })
      ).wait();

      // impersonate multisig account
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

      console.log(`\nAdd ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();

      console.log(`\nSet factory as trusted address of Divider so it can call setGuard()`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });

      console.log("\n-------------------------------------------------------");
      console.log(`Deploy adapters for: ${factoryContractName}`);
      for (let t of targets) {
        periphery = periphery.connect(deployerSigner);

        console.log(`\nAdd target ${t.name} to the whitelist`);
        await (await factoryContract.supportTarget(t.address, true)).wait();

        console.log(`\nOnboard target ${t.name} @ ${t.address} via ${factoryContractName}`);
        const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address, data);
        await (await periphery.deployAdapter(factoryAddress, t.address, data)).wait();
        console.log(`${t.name} adapter address: ${adapterAddress}`);

        console.log(`\nCan call scale value`);
        const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
        const scale = await adptr.callStatic.scale();
        console.log(`-> scale: ${scale.toString()}`);

        const params = await await divider.adapterMeta(adapterAddress);
        console.log(`-> adapter guard: ${params[2]}`);

        console.log(`\nApprove Periphery to pull stake...`);
        const ERC20_ABI = ["function approve(address spender, uint256 amount) public returns (bool)"];
        const stakeContract = new ethers.Contract(stake, ERC20_ABI, deployerSigner);
        await stakeContract.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        console.log(`Mint stake tokens...`);
        await generateStakeTokens(stake, deployer, deployerSigner);

        // deploy Series
        for (let m of t.series) {
          console.log(`\nSponsor Series for ${t.name} @ ${t.address} with maturity ${m}`);
          await periphery.callStatic.sponsorSeries(adapterAddress, m, false);
          await (await periphery.sponsorSeries(adapterAddress, m, false)).wait();
        }
      }

      console.log("\n-------------------------------------------------------");

      // Unset deployer and set multisig as trusted address
      console.log(`Set multisig as trusted address of 4626CropsFactory`);
      await (await factoryContract.setIsTrusted(senseAdminMultisigAddress, true)).wait();

      console.log(`Unset deployer as trusted address of 4626CropsFactory`);
      await (await factoryContract.setIsTrusted(deployer, false)).wait();

      // Unset deployer and set multisig as trusted address on 4626Factory (we forgot doing this on the prev task)
      console.log(`\nSet multisig as trusted address of 4626Factory`);
      await (await erc4626Factory.setIsTrusted(senseAdminMultisigAddress, true)).wait();

      console.log(`Unset deployer as trusted address of 4626Factory`);
      await (await erc4626Factory.setIsTrusted(deployer, true)).wait();

      // Unset deployer and set multisig as trusted address on MasterPriceOracle (we forgot doing this on the prev task)
      console.log(`\nSet multisig as trusted address of MasterPriceOracle`);
      await (await masterOracle.setIsTrusted(senseAdminMultisigAddress, true)).wait();

      console.log(`Unset deployer as trusted address of MasterPriceOracle`);
      await (await masterOracle.setIsTrusted(deployer, true)).wait();
    }

    if (VERIFY_CHAINS.includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
      console.log("\n1. Set factory on Periphery");
      console.log("\n2. Set factory as trusted on Divider");
      console.log("\n3. Deploy adapters on Periphery (if needed)");
      console.log("\n4. For each adapter, sponsor Series on Periphery");
      console.log("\n5. For each series, run capital seeder");
    }
  }
});
