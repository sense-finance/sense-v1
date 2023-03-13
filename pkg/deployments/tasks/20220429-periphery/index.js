const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { BALANCER_VAULT, SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const spaceFactoryAbi = require("./abi/SpaceFactory.json");
const poolManagerAbi = require("./abi/PoolManager.json");
const oldPeripheryAbi = require("./abi/OldPeriphery.json");
const newPeripheryAbi = require("./abi/NewPeriphery.json");

task("20220429-periphery", "Deploys and authenticates a new Periphery").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
  const balancerVault = BALANCER_VAULT.get(chainId);

  const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
  const spaceFactory = new ethers.Contract(mainnet.spaceFactory, spaceFactoryAbi, signer);
  const oldPeriphery = new ethers.Contract(mainnet.oldPeriphery, oldPeripheryAbi, signer);
  console.log([divider.address, spaceFactory.address, balancerVault]);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Periphery");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, spaceFactory.address, balancerVault],
    log: true,
  });

  console.log("\nOnboarding and verifying pre-approved adapters on Periphery");
  const adaptersOnboarded = (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterOnboarded(null))).map(
    e => e.args.adapter,
  );
  console.log("Adapters to onborad:", adaptersOnboarded);

  const adaptersVerified = (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterVerified(null))).map(
    e => e.args.adapter,
  );
  console.log("Adapters to verify:", adaptersVerified);

  const factoriesAddedArgs = (
    await oldPeriphery.queryFilter(oldPeriphery.filters.FactoryChanged(null, null))
  ).map(e => e.args);
  const addedFactoriesWithStatus = {};
  for (const { factory, isOn } of factoriesAddedArgs) {
    addedFactoriesWithStatus[factory] = isOn;
  }
  const factoriesAddedFiltered = [];
  for (const [factory, isOn] of Object.entries(addedFactoriesWithStatus)) {
    if (isOn) {
      factoriesAddedFiltered.push(factory);
    }
  }
  console.log("Factories to add:", factoriesAddedFiltered);

  const newPeriphery = new ethers.Contract(peripheryAddress, newPeripheryAbi, signer);

  for (let adapter of adaptersOnboarded) {
    console.log("Onboarding adapter (but don't need to add it again to the Divider)", adapter);
    await newPeriphery.onboardAdapter(adapter, false).then(t => t.wait());
  }

  for (let adapter of adaptersVerified) {
    console.log("Verifying adapter (but don't need to add it again to the Fuse pool)", adapter);
    await newPeriphery.verifyAdapter(adapter, false).then(t => t.wait());
  }

  for (let factory of factoriesAddedFiltered) {
    console.log("Adding factory", factory);
    await newPeriphery.setFactory(factory, true).then(t => t.wait());
  }

  console.log("\nAdding admin multisig as admin on Periphery");
  await newPeriphery.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());

  console.log("\nRemoving deployer as admin on Periphery");
  await newPeriphery.setIsTrusted(deployer, false).then(t => t.wait());

  // If we're in a forked environment, check the txs we need to send from the multisig as well
  if (chainId === CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    console.log("\nChecking multisig txs by impersonating the address");
    if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
    const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [senseAdminMultisigAddress],
    });
    const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

    const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    const poolManager = new ethers.Contract(mainnet.poolManager, poolManagerAbi, signer);
    const oldPeriphery = new ethers.Contract(mainnet.oldPeriphery, oldPeripheryAbi, signer);

    console.log("\nUnset the multisig as an authority on the old Periphery");
    await (await oldPeriphery.setIsTrusted(senseAdminMultisigAddress, false)).wait();

    console.log("\nSet the periphery on the Divider");
    await (await divider.setPeriphery(newPeriphery.address)).wait();

    console.log("\nRemove the old Periphery auth over the pool manager");
    await (await poolManager.setIsTrusted(oldPeriphery.address, false)).wait();

    console.log("\nGive the new Periphery auth over the pool manager");
    await (await poolManager.setIsTrusted(newPeriphery.address, true)).wait();
  }
});
