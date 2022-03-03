const fs = require('fs-extra');
const path = require('path');
const { exec } = require("child_process");
const log = console.log;

// More info here (https://kndrck.co/posts/local_erc20_bal_mani_w_hh/)
exports.STORAGE_SLOT = {
  DAI: 2,
  WETH: 3
};

// Copy deployments from `deployments` folder to `deployments_data` including tags folders 
exports.moveDeployments = async function() {
  const tag = await currentTag();
  const currentPath = path.join(__dirname, `deployments/${network.name == 'hardhat' ? 'localhost' : network.name }`);
  const destinationPath = path.join(__dirname, `deployments_data/${network.name == 'hardhat' ? 'localhost' : network.name }/${tag}/contracts`);
  try {
    await fs.copySync(currentPath, destinationPath);
    log(`\Deployed contracts successfully moved to ${destinationPath}`);
  } catch (err) {
    console.error(err)
  }                    
}

// Writes deployed contracts addresses (excluding adapters) into contracts.json 
exports.writeDeploymentsToFile = async function() {
  const tag = await currentTag();
  const currentPath = path.join(__dirname, `deployments_data/${network.name == 'hardhat' ? 'localhost' : network.name }/${tag}/contracts`);
  let addresses = {};
  try {
    const files = await fs.readdir(currentPath);
    await Promise.all(files.map(async item => {
      if (path.extname(item) == '.json') {
        const contract = await fs.readJson(`${currentPath}/${item}`)
        addresses[path.parse(item).name] = contract.address;
      }
    }))
    const destinationPath = `${currentPath}/../contracts.json`;
    await fs.writeJson(destinationPath, addresses);  
    log(`\Deployed contracts addresses successfully saved to ${currentPath}`);
  } catch (err) {
    console.error(err)
  }                    
}

// Writes deployed adapters addresses (without ABI) into adapters.json 
exports.writeAdaptersToFile = async function() {
  try {
    const tag = await currentTag();
    const deployedAdapters = await getDeployedAdapters(); 
    const destinationPath = path.join(__dirname, `deployments_data/${network.name == 'hardhat' ? 'localhost' : network.name }/${tag}`);
    await fs.writeJson(`${destinationPath}/adapters.json`, deployedAdapters);
    log(`\Deployed adapters addresses successfully saved to ${destinationPath}/adapters.json`);
  } catch (err) {
    console.error(err)
  }
}

async function getDeployedAdapters() {
  const signer = (await ethers.getSigners())[0];
  const divider = await ethers.getContract("Divider");
  const events = [...new Set(await divider.queryFilter(divider.filters.AdapterChanged(null, null, 1)))]; // fetch all deployed Adapters
  let deployedAdapters = {}; 
  await Promise.all(events.map(async (e) => {
    const ABI = [
      "function target() public view returns (address)",
      "function symbol() public view returns (string)",
    ];
    const adapter = new ethers.Contract(e.args.adapter, ABI, signer);
    const targetAddress = await adapter.target();
    const target = new ethers.Contract(targetAddress, ABI, signer);
    const symbol = await target.symbol();
    deployedAdapters[symbol] = e.args.adapter;
  }));
  return deployedAdapters;
}
exports.getDeployedAdapters = getDeployedAdapters;

async function currentTag() {
  const tag = await new Promise((resolve, reject) => {
    exec("git describe --abbrev=0", (error, stdout, stderr) => {
      if (error) {
        reject(error);
      }
      resolve(stdout ? stdout : stderr);
    });
  });
  return tag.trim().replace(/(\r\n|\n|\r)/gm, "");
}
exports.currentTag = currentTag;

exports.toBytes32 = (bn) => {
  return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
};

exports.setStorageAt = async (address, index, value) => {
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};
