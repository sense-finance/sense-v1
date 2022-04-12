const { network } = require("hardhat");
const { moveDeployments, writeDeploymentsToFile, writeAdaptersToFile } = require("../../hardhat.utils");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);

  const chainId = await getChainId();
  const divider = await ethers.getContract("Divider", signer);
  const periphery = await ethers.getContract("Periphery", signer);

  log("\n-------------------------------------------------------");
  log("DEPLOY FACTORIES & ADAPTERS");
  log("-------------------------------------------------------");
  for (let factory of global.mainnet.FACTORIES) {
    const { contractName, adapterContract, reward, ifee, stake, stakeSize, minm, maxm, mode, oracle, tilt, targets } =
      factory(chainId);
    if (!reward) throw Error("No reward token found");
    if (!stake) throw Error("No stake token found");

    log(`\nDeploy ${contractName}`);
    const factoryParams = [oracle, ifee, stake, stakeSize, minm, maxm, mode, tilt];
    const { address: factoryAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });

    log(`Trust ${contractName} on the divider`);
    await (await divider.setIsTrusted(factoryAddress, true)).wait();

    log(`Add ${contractName} support to Periphery`);
    await (await periphery.setFactory(factoryAddress, true)).wait();

    log("\n-------------------------------------------------------");
    log(`DEPLOY ADAPTERS FOR: ${contractName}`);
    log("-------------------------------------------------------");
    for (let target of targets) {
      const { name, address, guard } = target;

      log(`\nDeploy ${name} adapter`);
      const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, address);
      await (await periphery.deployAdapter(factoryAddress, address)).wait();

      log(`Set ${name} adapter issuance cap to ${guard}`);
      await divider.setGuard(adapterAddress, guard).then(tx => tx.wait());

      log(`Can call scale value`);
      const { abi: adapterAbi } = await deployments.getArtifact(adapterContract);
      const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
      const scale = await adapter.callStatic.scale();
      log(`-> scale: ${scale.toString()}`);
    }
  }

  log("\n-------------------------------------------------------");
  log("DEPLOY ADAPTERS WITHOUT FACTORY");
  log("-------------------------------------------------------");
  for (let adapter of global.mainnet.ADAPTERS) {
    const { contractName, adapterParams, target } = adapter(chainId);
    // if (!stake) throw Error("No stake token found");

    log(`\nDeploy ${contractName}`);
    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, adapterParams],
      log: true,
    });

    log(`Set ${contractName} adapter issuance cap to ${target.guard}`);
    await divider.setGuard(adapterAddress, target.guard).then(tx => tx.wait());

    log(`Verify ${contractName} adapter`);
    await periphery.verifyAdapter(adapterAddress, true).then(tx => tx.wait());

    log(`Onboard ${contractName} adapter`);
    await periphery.onboardAdapter(adapterAddress, true).then(tx => tx.wait());

    log(`Can call scale value`);
    const { abi: adapterAbi } = await deployments.getArtifact(contractName);
    const adptr = new ethers.Contract(adapterAddress, adapterAbi, signer);
    const scale = await adptr.callStatic.scale();
    log(`-> scale: ${scale.toString()}`);
  }

  if (!process.env.CI && hre.config.networks[network.name].saveDeployments) {
    log("\n-------------------------------------------------------");
    await moveDeployments();
    await writeDeploymentsToFile();
    await writeAdaptersToFile();
  }
};

module.exports.tags = ["prod:factories", "scenario:prod"];
module.exports.dependencies = ["prod:periphery"];
