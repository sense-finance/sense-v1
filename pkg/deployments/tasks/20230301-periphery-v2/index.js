const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS, VERIFY_CHAINS } = require("../../hardhat.addresses");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task("20230301-periphery-v2", "Deploys and authenticates Periphery V2").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  const { abi: dividerAbi } = await deployments.getArtifact("Divider");
  const { abi: peripheryAbi } = await deployments.getArtifact("Periphery");
  const { abi: rlvFactoryAbi } = await deployments.getArtifact("AutoRollerFactory");
  const { abi: rlvAbi } = await deployments.getArtifact("AutoRoller");

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

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
  // const { address: peripheryAddress } = await deploy("Periphery", {
  //   from: deployer,
  //   args: [divider.address, spaceFactoryAddress, balancerVaultAddress, permit2Address, exchangeProxyAddress],
  //   log: true,
  // });
  const peripheryAddress = "0x1dc2cff5451b839d83b6d2598779c90f34cd3bc7";
  const newPeriphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  console.log(`Periphery deployed to ${peripheryAddress}`);

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

  // We are only onboarding and verifying adapters whose guard is > 0
  // We can also assume all our onboarded adapters are verified (we have NO un-verified adapters so far)
  console.log("\nOnboarding and verifying pre-approved adapters on Periphery");
  const adaptersOnboarded = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterOnboarded(null))).map(e => e.args.adapter),
    ),
  ];
  console.log("Adapters to verify & onboard:", adaptersOnboarded);

  let onboarded = [
    "0x36c744Dd2916E9E04173Bee9d93D554f955a999d".toLowerCase(),
    "0x6fC4843aac4786b4420e954a2271BE16f225a482".toLowerCase(),
    "0x2C4D2Ba7C6Cb6Fb7AD67d76201cfB22B174B2C4b".toLowerCase(),
    "0x60fe5A21A4a8529c3d94e4B1d52f6Dae2d289dC5".toLowerCase(),
    "0x9887e67AaB4388eA4cf173B010dF5c92B91f55B5".toLowerCase(),
    "0x66E1AD7cDa66A0B291aEC63f3dBD8cB9eAF76680".toLowerCase(),
    "0x529c90E6d3a1AedaB9B3011196C495439D23b893".toLowerCase(),
    "0x8c5e7301a012DC677DD7DaD97aE44032feBCD0FD".toLowerCase(),
    "0x86c55BFFb64f8fCC8beA33F3176950FDD0fb160D".toLowerCase(),
  ]

  let verified = [
    "0x36c744Dd2916E9E04173Bee9d93D554f955a999d".toLowerCase(),
    "0x6fC4843aac4786b4420e954a2271BE16f225a482".toLowerCase(),
    "0x2C4D2Ba7C6Cb6Fb7AD67d76201cfB22B174B2C4b".toLowerCase(),
    "0x60fe5A21A4a8529c3d94e4B1d52f6Dae2d289dC5".toLowerCase(),
    "0x9887e67AaB4388eA4cf173B010dF5c92B91f55B5".toLowerCase(),
    "0x66E1AD7cDa66A0B291aEC63f3dBD8cB9eAF76680".toLowerCase(),
    "0x529c90E6d3a1AedaB9B3011196C495439D23b893".toLowerCase(),
    "0x8c5e7301a012DC677DD7DaD97aE44032feBCD0FD".toLowerCase(),
    // "0x86c55BFFb64f8fCC8beA33F3176950FDD0fb160D".toLowerCase(), PENDING
  ]

  for (let adapter of adaptersOnboarded) {
    console.log("\nOnboarding adapter", adapter);
    const params = await divider.adapterMeta(adapter);
    if (params[2].gt(0)) {
      if (!onboarded.includes(adapter.toLowerCase())) {
        await newPeriphery.onboardAdapter(adapter, false).then(t => t.wait());
        console.log(`- Adapter ${adapter} onboarded`);
      } else {
        console.log(`- Skipped adapter ${adapter} onboarding as it's already onboarded`);
      }
      if (!verified.includes(adapter.toLowerCase())) {
        await newPeriphery.verifyAdapter(adapter).then(t => t.wait());
        console.log(`- Adapter ${adapter} verified`);
      } else {
        console.log(`- Skipped adapter ${adapter} verification as it's already verified`);
      }
    } else {
      console.log(`- Skipped adapter ${adapter} verification as it's guard is ${params[2]}`);
    }
  }

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
      await newPeriphery.setFactory(factory, true).then(t => t.wait());
      console.log(`- Factory ${factory} onboarded`);
    } else {
      console.log(`- Skipped ${factory} as it has been unverified`);
    }
  }

  console.log("\nUpdate Periphery address on existing RLVs");
  const rlvs = [
    ...new Set(
      (await rlvFactory.queryFilter(rlvFactory.filters.RollerCreated(null))).map(e => e.args.autoRoller),
    ),
  ];
  console.log("RLVs to update:", rlvs);
  for (let rlvAddress of rlvs) {
    const rlv = new ethers.Contract(rlvAddress, rlvAbi, deployerSigner);
    await rlv["setParam(bytes32,address)"](
      ethers.utils.formatBytes32String("PERIPHERY"),
      peripheryAddress,
    ).then(t => t.wait());
    console.log(`- Periphery address successfully updated on RLV ${rlv}`);

    await rlv["setParam(bytes32,address)"](
      ethers.utils.formatBytes32String("OWNER"),
      senseAdminMultisigAddress,
    ).then(t => t.wait());
    console.log(`- Owner successfully updated on RLV ${rlv}`);
  }

  if (senseAdminMultisigAddress.toUpperCase() !== deployer.toUpperCase()) {
    console.log("\nAdding admin multisig as admin on Periphery");
    await newPeriphery.setIsTrusted(senseAdminMultisigAddress, true).then(t => t.wait());

    console.log("\nRemoving deployer as admin on Periphery");
    await newPeriphery.setIsTrusted(deployer, false).then(t => t.wait());
  }

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan("Periphery");
  } else {
    // If we're in a forked environment, check the txs we need to send from the multisig as wel
    console.log(`\nFund multisig to be able to make calls from that address`);
    await deployerSigner
      .sendTransaction({
        to: senseAdminMultisigAddress,
        value: ethers.utils.parseEther("1"),
      })
      .then(t => t.wait());

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [senseAdminMultisigAddress],
    });

    const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
    oldPeriphery = oldPeriphery.connect(multisigSigner);
    divider = divider.connect(multisigSigner);

    if (senseAdminMultisigAddress.toUpperCase() !== deployer.toUpperCase()) {
      console.log("\nUnset the multisig as an authority on the old Periphery");
      await oldPeriphery.setIsTrusted(senseAdminMultisigAddress, false).then(t => t.wait());
    }
  }

  if ([CHAINS.GOERLI, CHAINS.HARDHAT].includes(chainId)) {
    console.log("\nSet the periphery on the Divider");
    await divider.setPeriphery(peripheryAddress).then(t => t.wait());
  }

  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
    console.log("\n1. Unset the multisig as an authority on the old Periphery");
    console.log("\n2. Set the periphery on the Divider");
  }

  // Get deployer's balance after deployment
  const finalBalance = await deployerSigner.getBalance();
  console.log(`Deployer's final balance: ${ethers.utils.formatEther(finalBalance)} ETH`);

  // Calculate the cost
  const cost = initialBalance.sub(finalBalance);
  console.log(`Deployment cost: ${ethers.utils.formatEther(cost)} ETH`);

  console.log("\n-------------------------------------------------------");
});
