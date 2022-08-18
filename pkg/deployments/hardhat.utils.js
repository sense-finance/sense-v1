const fs = require("fs-extra");
const path = require("path");
const { exec } = require("child_process");
const log = console.log;
const { DefenderRelayProvider, DefenderRelaySigner } = require("defender-relay-client/lib/ethers");

// More info here (https://kndrck.co/posts/local_erc20_bal_mani_w_hh/)
exports.STORAGE_SLOT = {
  DAI: 2,
  wstETH: 0,
  WETH: 3,
  USDC: 9,
};

// Copy deployments from `deployments` folder to `deployed` including versions folders
exports.moveDeployments = async function () {
  const version = await currentVersion();
  const currentPath = path.join(
    __dirname,
    `deployments/${network.name == "hardhat" ? "localhost" : network.name}`,
  );
  const destinationPath = path.join(
    __dirname,
    `deployed/${network.name == "hardhat" ? "localhost" : network.name}/${version}/contracts`,
  );
  try {
    await fs.copySync(currentPath, destinationPath);
    log(`\nDeployed contracts successfully moved to ${destinationPath}`);
  } catch (err) {
    console.error(err);
  }
};

// Writes deployed contracts addresses (excluding adapters) into contracts.json
exports.writeDeploymentsToFile = async function () {
  const version = await currentVersion();
  const currentPath = path.join(
    __dirname,
    `deployed/${network.name == "hardhat" ? "localhost" : network.name}/${version}/contracts`,
  );
  let addresses = {};
  try {
    const files = await fs.readdir(currentPath);
    await Promise.all(
      files.map(async item => {
        if (path.extname(item) == ".json") {
          const contract = await fs.readJson(`${currentPath}/${item}`);
          addresses[path.parse(item).name] = contract.address;
        }
      }),
    );
    const destinationPath = `${currentPath}/../contracts.json`;
    await fs.writeJson(destinationPath, addresses);
    log(`\nDeployed contracts addresses successfully saved to ${currentPath}`);
  } catch (err) {
    console.error(err);
  }
};

// Writes deployed adapters addresses (without ABI) into adapters.json
exports.writeAdaptersToFile = async function () {
  try {
    const version = await currentVersion();
    const deployedAdapters = await getDeployedAdapters();
    const destinationPath = path.join(
      __dirname,
      `deployed/${network.name == "hardhat" ? "localhost" : network.name}/${version}`,
    );
    await fs.writeJson(`${destinationPath}/adapters.json`, deployedAdapters);
    log(`\nDeployed adapters addresses successfully saved to ${destinationPath}/adapters.json`);
  } catch (err) {
    console.error(err);
  }
};

async function getDeployedAdapters() {
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const divider = await ethers.getContract("Divider", signer);
  const events = [...new Set(await divider.queryFilter(divider.filters.AdapterChanged(null, null, 1)))]; // fetch all deployed Adapters
  let deployedAdapters = {};
  await Promise.all(
    events.map(async e => {
      const ABI = [
        "function target() public view returns (address)",
        "function symbol() public view returns (string)",
      ];
      const adapter = new ethers.Contract(e.args.adapter, ABI, signer);
      const targetAddress = await adapter.target();
      const target = new ethers.Contract(targetAddress, ABI, signer);
      const symbol = await target.symbol();
      deployedAdapters[symbol] = e.args.adapter;
    }),
  );
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

async function currentVersion() {
  const pkgjson = JSON.parse(fs.readFileSync(`${__dirname}/../../package.json`, "utf-8"));
  return `v${pkgjson.version}`;
}
exports.currentVersion = currentVersion;

exports.toBytes32 = bn => {
  return ethers.utils.hexlify(ethers.utils.zeroPad(bn.toHexString(), 32));
};

async function setStorageAt(address, index, value) {
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
}
exports.setStorageAt = setStorageAt;

const delay = n => new Promise(r => setTimeout(r, n * 1000));
exports.delay = delay;

exports.verifyOnEtherscan = async (address, constructorArguments) => {
  await new Promise((resolve, reject) => {
    exec("hardhat clean", (error, stdout, stderr) => {
      if (error) {
        reject(error);
      }
      resolve(stdout ? stdout : stderr);
    });
  });
  console.log("Waiting 20 seconds for Etherscan to sync...");
  await delay(20);
  console.log("Trying to verify contract on Etherscan...");
  try {
    await hre.run("verify:verify", {
      address,
      constructorArguments,
    });
  } catch (e) {
    console.log(e);
    console.log("We couldn't verify the contract on Etherscan, you may try manually.");
  }
};

exports.generateStakeTokens = async (stakeAddress, to, signer) => {
  const ERC20_ABI = ["function symbol() public view returns (string)"];
  const stake = new ethers.Contract(stakeAddress, ERC20_ABI, signer);
  const symbol = await stake.symbol();

  // Get storage slot index
  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    [to, this.STORAGE_SLOT[symbol] || 2], // key, slot
  );

  await setStorageAt(
    stakeAddress,
    index.toString(),
    this.toBytes32(ethers.utils.parseEther("10000")).toString(),
  );
  log(`\n10'000 ${symbol} transferred to deployer: ${to}`);
};

// Returns signer using OZ Relayer's API
exports.getRelayerSigner = async () => {
  const { RELAYER_API_KEY_MAINNET, RELAYER_API_SECRET_MAINNET } = process.env;
  const credentials = { apiKey: RELAYER_API_KEY_MAINNET, apiSecret: RELAYER_API_SECRET_MAINNET };
  const provider = new DefenderRelayProvider(credentials);
  return new DefenderRelaySigner(credentials, provider, { speed: "fast" });
};
