const { network } = require("hardhat");
const { moveDeployments, writeDeploymentsToFile, writeAdaptersToFile } = require("../../hardhat.utils");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  
  const chainId = await getChainId();
  const divider = await ethers.getContract("Divider");
  const periphery = await ethers.getContract("Periphery");
  
  log("\n-------------------------------------------------------")
  log("DEPLOY FACTORIES & ADAPTERS")
  log("-------------------------------------------------------")
  for (let factory of global.mainnet.FACTORIES) {
    const { contractName, adapterContract, reward, ifee, stake, stakeSize, minm, maxm, mode, oracle, tilt, targets } = factory(chainId);
    if (!reward) throw Error("No reward token found");
    if (!stake) throw Error("No stake token found");

    log(`\nDeploy ${contractName}`);
    const factoryParams = [oracle, ifee, stake, stakeSize, minm, maxm, mode, tilt];
    const { address: cFactoryAddress } = await deploy("CFactory", {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });

    log(`Trust ${contractName} on the divider`);
    await (await divider.setIsTrusted(cFactoryAddress, true)).wait();
  
    log(`Add ${contractName} support to Periphery`);
    await (await periphery.setFactory(cFactoryAddress, true)).wait();
    
    log("\n-------------------------------------------------------")
    log(`DEPLOY ADAPTERS FOR: ${contractName}`);
    log("-------------------------------------------------------")
    for (let target of targets) {
      const { name, address, guard } = target;
      
      log(`\nDeploy ${name} adapter`);
      const adapterAddress = await periphery.callStatic.deployAdapter(cFactoryAddress, address);
      await (await periphery.deployAdapter(cFactoryAddress, address)).wait();

      log(`Set ${name} adapter issuance cap to max uint so we don't have to worry about it`);
      await divider.setGuard(adapterAddress, guard).then(tx => tx.wait());
      
      log(`Can call scale value`);
      const { abi: adapterAbi } = await deployments.getArtifact(adapterContract);
      const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
      const scale = await adapter.callStatic.scale();
      log(`-> scale: ${scale.toString()}`);
    }
  }
  if (!process.env.CI && hre.config.networks[network.name].saveDeployments) {
    log("\n-------------------------------------------------------")
    await moveDeployments();
    await writeDeploymentsToFile();
    await writeAdaptersToFile();
  }
  
};

module.exports.tags = ["prod:factories", "scenario:prod"];
module.exports.dependencies = ["prod:periphery"];
