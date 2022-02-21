const fs = require("fs");
const { exec } = require("child_process");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  
  const chainId = await getChainId();
  const divider = await ethers.getContract("Divider");
  const periphery = await ethers.getContract("Periphery");
  
  for (let factory of global.mainnet.FACTORIES) {
    const { contractName, adapterContract, reward, ifee, stake, stakeSize, minm, maxm, mode, oracle, tilt, targets } = factory(chainId);
    if (!reward) throw Error("No reward token found");
    if (!stake) throw Error("No stake token found");
    console.log(`\nDeploy ${contractName}`);
    const factoryParams = [oracle, ifee, stake, stakeSize, minm, maxm, mode, tilt];
    const { address: cFactoryAddress } = await deploy("CFactory", {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });

    console.log(`Trust ${contractName} on the divider`);
    await (await divider.setIsTrusted(cFactoryAddress, true)).wait();
  
    console.log(`Add ${contractName} support to Periphery`);
    await (await periphery.setFactory(cFactoryAddress, true)).wait();
    
    console.log(`\nDeploy Adapters for ${contractName} adapter factory`);
    for (let target of targets) {
      const { name, address, guard } = target;
      
      console.log(`Deploy ${name} adapter`);
      const adapterAddress = await periphery.callStatic.deployAdapter(cFactoryAddress, address);
      await (await periphery.deployAdapter(cFactoryAddress, address)).wait();

      console.log(`Set ${name} adapter issuance cap to max uint so we don't have to worry about it`);
      await divider.setGuard(adapterAddress, guard).then(tx => tx.wait());
      
      console.log(`Can call scale value`);
      const { abi: adapterAbi } = await deployments.getArtifact(adapterContract);
      const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
      const scale = await adapter.callStatic.scale();
      console.log(`-> scale: ${scale.toString()}`);

      global.mainnet.ADAPTERS[name] = { address: adapterAddress, abi: adapterAbi }
    }
  }

  if (!process.env.CI) {
    await writeAdaptersToFile();
  }
  
  async function writeAdaptersToFile() {
    const currentTag = await new Promise((resolve, reject) => {
      exec("git describe --abbrev=0", (error, stdout, stderr) => {
        if (error) {
          reject(error);
        }
        resolve(stdout ? stdout : stderr);
      });
    });

    const deploymentDir = `./adapter-deployments/${currentTag.trim().replace(/(\r\n|\n|\r)/gm, "")}/`;
    fs.mkdirSync(deploymentDir, { recursive: true });
    fs.writeFileSync(`./${deploymentDir}/adapters.json`, JSON.stringify({ addresses: global.dev.ADAPTERS }));
  }
};

module.exports.tags = ["prod:factories", "scenario:prod"];
module.exports.dependencies = ["prod:periphery"];
