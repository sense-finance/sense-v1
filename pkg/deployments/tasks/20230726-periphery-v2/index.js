const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS, VERIFY_CHAINS } = require("../../hardhat.addresses");
const { verifyOnEtherscan, fund, generateTokens, boostedGasPrice } = require("../../hardhat.utils");
const { startPrank } = require("../../hardhat.utils");

task("20230726-periphery-v2", "Deploys and authenticates Periphery V2").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  const { abi: dividerAbi } = await deployments.getArtifact("Divider");
  const { abi: peripheryAbi } = await deployments.getArtifact("Periphery");
  const { abi: rlvFactoryAbi } = await deployments.getArtifact("AutoRollerFactory");
  const { abi: rlvAbi } = await deployments.getArtifact("AutoRoller");
  const { abi: adapterAbi } = await deployments.getArtifact("BaseAdapter");
  const { abi: erc20Abi } = await deployments.getArtifact("solmate/src/tokens/ERC20.sol:ERC20");

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
  const multisigSigner = await ethers.getSigner(senseAdminMultisigAddress);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  // Get deployer's balance before deployment
  const initialBalance = await deployerSigner.getBalance();
  console.log(`Deployer's initial balance: ${ethers.utils.formatEther(initialBalance)} ETH`);

  const {
    divider: dividerAddress,
    periphery: oldPeripheryAddress,
    spaceFactory: spaceFactoryAddress,
    balancerVault: balancerVaultAddress,
    permit2: permit2Address,
    exchangeProxy: exchangeProxyAddress,
    rlvFactory: rlvFactoryAddress,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let oldPeriphery = new ethers.Contract(oldPeripheryAddress, peripheryAbi, deployerSigner);
  let rlvFactory = new ethers.Contract(rlvFactoryAddress, rlvFactoryAbi, deployerSigner);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Periphery");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, spaceFactoryAddress, balancerVaultAddress, permit2Address, exchangeProxyAddress],
    log: true,
  });
  // const peripheryAddress = "0xAe90a191999DfA22d42c2D704f4712D6eb3cB0B3";
  let newPeriphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  console.log(`Periphery deployed to ${peripheryAddress}`);

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan("Periphery");
  }

  const Periphery = await ethers.getContractFactory("Periphery");
  const gasPrice = await ethers.provider.getGasPrice();

  // Create a deployment transaction with the same arguments
  const deploymentTransaction = Periphery.getDeployTransaction(
    divider.address,
    spaceFactoryAddress,
    balancerVaultAddress,
    permit2Address,
    exchangeProxyAddress,
  );

  // Estimate the gas required for the deployment transaction
  const gasEstimate = await ethers.provider.estimateGas(deploymentTransaction);

  // Calculate the estimated cost
  const estimatedCost = gasPrice.mul(gasEstimate);
  console.log(`Estimated deployment cost: ${ethers.utils.formatEther(estimatedCost)} ETH`);

  console.log("\n-------------------------------------------------------");
  console.log("\n---------ADAPTERS ONBOARDING/VERIFICATION--------------");
  console.log("\n-------------------------------------------------------");

  // We are only onboarding and verifying adapters whose guard is > 0
  console.log("\nOnboarding pre-onboarded adapters on Periphery");
  const adaptersOnboardedInOldPeriphery = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterOnboarded(null))).map(e => e.args.adapter),
    ),
  ];
  console.log(
    `${adaptersOnboardedInOldPeriphery.length} adapters already onboarded on new Periphery:`,
    adaptersOnboardedInOldPeriphery,
  );

  // Adapters that have been onboarded on the new Periphery
  const adaptersOnboardedInNewPeriphery = [
    ...new Set(
      (await newPeriphery.queryFilter(newPeriphery.filters.AdapterOnboarded(null))).map(e => e.args.adapter),
    ),
  ];
  console.log(
    `${adaptersOnboardedInNewPeriphery.length} adapters already onboarded on new Periphery:`,
    adaptersOnboardedInNewPeriphery,
  );

  console.log("\nVerifying pre-verified adapters on Periphery");
  const adaptersVerifiedInOldPeriphery = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterVerified(null))).map(e => e.args.adapter),
    ),
  ];
  console.log(
    `${adaptersVerifiedInOldPeriphery.length} adapters already verified on new Periphery:`,
    adaptersVerifiedInOldPeriphery,
  );

  // Adapters that have been already verified on the new Periphery
  const adaptersVerifiedInNewPeriphery = [
    ...new Set(
      (await newPeriphery.queryFilter(newPeriphery.filters.AdapterVerified(null))).map(e => e.args.adapter),
    ),
  ];
  console.log(
    `${adaptersVerifiedInNewPeriphery.length} adapters already verified on new Periphery:`,
    adaptersVerifiedInNewPeriphery,
  );

  const onboardedDifference = adaptersOnboardedInOldPeriphery.filter(
    x => !adaptersOnboardedInNewPeriphery.includes(x),
  );
  const verifiedDifference = adaptersVerifiedInOldPeriphery.filter(
    x => !adaptersVerifiedInNewPeriphery.includes(x),
  );

  console.log(
    `\n${onboardedDifference.length} adapters yet to be onboarded on new Periphery:`,
    onboardedDifference,
  );
  console.log(
    `${verifiedDifference.length} adapters yet to be verified on new Periphery:`,
    verifiedDifference,
  );

  // new Periphery's owner is deployer (first run of this script), we can call functions directly
  // otherwise, we would need to do it through the multisig
  // if fork from mainnet, set newPeriphery's signer with sense admin multisig
  if (chainId == CHAINS.HARDHAT && (await newPeriphery.isTrusted(senseAdminMultisigAddress))) {
    await startPrank(senseAdminMultisigAddress);
    console.log(`\nFund multisig to be able to make calls from that address`);
    await fund(deployerSigner, senseAdminMultisigAddress, ethers.utils.parseEther("1"));
    newPeriphery = newPeriphery.connect(multisigSigner);
  }

  // Onboard adapters
  for (let adapter of onboardedDifference) {
    console.log("\nOnboarding adapter", adapter);
    const params = await divider.adapterMeta(adapter);
    if (params[2].gt(0)) {
      await newPeriphery.onboardAdapter(adapter, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());
      console.log(`- Adapter ${adapter} onboarded`);
    } else {
      console.log(`- Skipped adapter ${adapter} verification as it's guard is ${params[2]}`);
    }
  }

  // Verify adapters
  for (let adapter of verifiedDifference) {
    console.log("\nVerifying adapter", adapter);
    const params = await divider.adapterMeta(adapter);
    if (params[2].gt(0)) {
      // if (adapter.toLowerCase() == "0x2C4D2Ba7C6Cb6Fb7AD67d76201cfB22B174B2C4b".toLowerCase()) {
      //   console.log(`Drop and replace...`, )
      //   await newPeriphery.verifyAdapter(adapter, { nonce: await ethers.provider.getTransactionCount(deployer), gasPrice: boostedGasPrice }).then(t => t.wait());
      // } else {
      await newPeriphery.verifyAdapter(adapter, { gasPrice: boostedGasPrice() }).then(t => t.wait());
      // }
      console.log(`- Adapter ${adapter} verified`);
    } else {
      console.log(`- Skipped adapter ${adapter} verification as it's guard is ${params[2]}`);
    }
  }

  console.log("\n-------------------------------------------------------");
  console.log("\n----------------FACTORIES ONBOARDING-------------------");
  console.log("\n-------------------------------------------------------");

  console.log("\nVerifying pre-approved factories on Periphery");
  const factoriesOnboarded = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.FactoryChanged(null))).map(e => e.args.factory),
    ),
  ];
  console.log("Factories to onboard:", factoriesOnboarded);
  for (let factory of factoriesOnboarded) {
    console.log(`\nOnboarding factory ${factory}...`);
    if (await oldPeriphery.factories(factory)) {
      if (await newPeriphery.factories(factory)) {
        console.log(`- Skipped ${factory} as it's already onboarded`);
      } else {
        await newPeriphery.setFactory(factory, true, { gasPrice: boostedGasPrice() }).then(t => t.wait());
        console.log(`- Factory ${factory} onboarded`);
      }
    } else {
      console.log(`- Skipped ${factory} as it has been unverified`);
    }
  }

  console.log("\n-------------------------------------------------------");
  console.log("\n----------------SET/UNSET TRUSTED ADDRS----------------");
  console.log("\n-------------------------------------------------------");

  if (senseAdminMultisigAddress.toUpperCase() !== deployer.toUpperCase()) {
    console.log("\nAdding admin multisig as trusted address on Periphery");
    if (!(await newPeriphery.isTrusted(senseAdminMultisigAddress))) {
      await newPeriphery
        .setIsTrusted(senseAdminMultisigAddress, true, { gasPrice: boostedGasPrice() })
        .then(t => t.wait());
    } else {
      console.log(`- Skipped ${senseAdminMultisigAddress} as it's already a trusted address`);
    }

    console.log("\nRemoving deployer as trusted address on Periphery");
    if (await newPeriphery.isTrusted(deployer)) {
      await newPeriphery.setIsTrusted(deployer, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());
    } else {
      console.log(`- Skipped ${deployer} as it's already not a trusted address`);
    }
  }

  console.log("\n-------------------------------------------------------");
  console.log("\n----------------RLVS PERIPHERY UPDATING-----------------");
  console.log("\n-------------------------------------------------------");

  // Impersonate multisig if fork from mainnet && fund it
  if (chainId == CHAINS.HARDHAT) {
    await startPrank(senseAdminMultisigAddress);
    await fund(deployerSigner, senseAdminMultisigAddress, ethers.utils.parseEther("1"));

    // Update Periphery address on existing RLVs (requires multisig)
    console.log("\nUpdate Periphery address on existing RLVs");
    const rlvs = [
      ...new Set(
        (await rlvFactory.queryFilter(rlvFactory.filters.RollerCreated(null))).map(e => e.args.autoRoller),
      ),
    ];

    console.log("RLVs to update:", rlvs);
    for (let rlvAddress of rlvs) {
      const rlv = new ethers.Contract(rlvAddress, rlvAbi, multisigSigner);

      console.log("\n-------------------------------------------------------");
      const adptr = new ethers.Contract(await rlv.adapter(), adapterAbi, deployerSigner);
      console.log(`\nUpdating RLV @ ${rlv.address} whose adapter is ${await adptr.name()}`);

      const rlvPeriphery = await getInternalVar(7, rlvAddress);
      console.log(`\nRLV periphery is: ${rlvPeriphery}`);
      if (rlvPeriphery.toUpperCase() !== newPeriphery.address.toUpperCase()) {
        await rlv["setParam(bytes32,address)"](
          ethers.utils.formatBytes32String("PERIPHERY"),
          peripheryAddress,
          { gasPrice: boostedGasPrice() },
        ).then(t => t.wait());
        console.log(`- Periphery address successfully updated on RLV ${rlv.address}`);
      } else {
        console.log(`- Skipped periphery address update on RLV ${rlv.address} as it's already set`);
      }

      const rlvOwner = await getInternalVar(9, rlvAddress);
      console.log(`\nRLV owner is: ${rlvOwner}`);
      if (rlvOwner.toUpperCase() !== senseAdminMultisigAddress.toUpperCase()) {
        await rlv["setParam(bytes32,address)"](
          ethers.utils.formatBytes32String("OWNER"),
          senseAdminMultisigAddress,
          { gasPrice: boostedGasPrice() },
        ).then(t => t.wait());
        console.log(`- Owner successfully updated on RLV ${rlv.address}`);
      } else {
        console.log(`- Skipped owner update on RLV ${rlv.address} as it's already set`);
      }
    }

    oldPeriphery = oldPeriphery.connect(multisigSigner);
    divider = divider.connect(multisigSigner);

    // if (senseAdminMultisigAddress.toUpperCase() !== deployer.toUpperCase()) {
    //   console.log("\nUnset the multisig as an authority on the old Periphery");
    //   if (await oldPeriphery.isTrusted(senseAdminMultisigAddress)) {
    //     await oldPeriphery.setIsTrusted(senseAdminMultisigAddress, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());
    //   }
    // }
  }

  if ([CHAINS.GOERLI, CHAINS.HARDHAT].includes(chainId)) {
    console.log("\nSet the periphery on the Divider");
    await divider.setPeriphery(peripheryAddress, { gasPrice: boostedGasPrice() }).then(t => t.wait());
  }

  // Get deployer's balance after deployment
  const finalBalance = await deployerSigner.getBalance();
  console.log(`Deployer's final balance: ${ethers.utils.formatEther(finalBalance)} ETH`);

  // Calculate the cost
  const cost = initialBalance.sub(finalBalance);
  console.log(`Deployment cost: ${ethers.utils.formatEther(cost)} ETH`);

  console.log("\n-------------------------------------------------------");
  console.log("\n-----------------SANITY CHECKS-------------------------");
  console.log("\n-------------------------------------------------------");

  console.log("\nTry rolling RLVs");
  const rlvs = [
    ...new Set(
      (await rlvFactory.queryFilter(rlvFactory.filters.RollerCreated(null))).map(e => e.args.autoRoller),
    ),
  ];

  for (let rlvAddress of rlvs) {
    console.log(`\nRLV is: ${rlvAddress}`);
    const rlvOwner = await getInternalVar(9, rlvAddress);
    console.log(`RLV owner is: ${rlvOwner}`);

    await startPrank(deployer);

    let rlv = new ethers.Contract(rlvAddress, rlvAbi, deployerSigner);
    const adptr = new ethers.Contract(await rlv.adapter(), adapterAbi, deployerSigner);
    const [targetAddress, stakeAddress] = await adptr.getStakeAndTarget();

    // generate stake tokens
    const stakeSize = ethers.utils.parseEther("0.25");
    await generateTokens(stakeAddress, deployer, deployerSigner, stakeSize);

    // approve RLV to pull stake
    const stake = new ethers.Contract(stakeAddress, erc20Abi, deployerSigner);
    await (await stake.approve(rlv.address, stakeSize, { gasPrice: boostedGasPrice() })).wait();

    let skip = false;
    // if this is the RLV's first roll, we need to generate some target tokens for the first deposit
    if ((await rlv.lastSettle()).eq(0)) {
      // sometimes we can't find the slot so we fail at generating the tokens
      // so we will skip this RLV from the sanity checks
      try {
        const firstDeposit = ethers.utils.parseEther("1");
        await generateTokens(targetAddress, deployer, deployerSigner, firstDeposit);
        // approve RLV to pull target (for first roll RLVs)
        const target = new ethers.Contract(targetAddress, erc20Abi, deployerSigner);
        await (await target.approve(rlv.address, firstDeposit, { gasPrice: boostedGasPrice() })).wait();
      } catch (e) {
        skip = true;
        console.log(`- Skipping RLV ${rlv.address} as we couldn't generate target tokens for it`);
      }
    }

    if (!skip) {
      await rlv.roll({ gasPrice: boostedGasPrice() }).then(t => t.wait());
      console.log(`- RLV successfully rolled`);
    }
  }

  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
    console.log("\n1. Unset the multisig as an authority on the old Periphery");
    console.log("\n2. Set the periphery on the Divider");
    console.log("\n3. Update each RLV with the new Periphery address");
  }
});

async function getInternalVar(slot, contractAddress) {
  const paddedSlot = ethers.utils.hexZeroPad(slot, 32);
  const value = await ethers.provider.getStorageAt(contractAddress, paddedSlot);
  return ethers.utils.hexStripZeros(value);
}
