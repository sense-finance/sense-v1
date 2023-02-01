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
  maDAI: 51,
  maUSDC: 51,
  maUSDT: 51,
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

async function setBalance(address, value) {
  await network.provider.send("hardhat_setBalance", [address, `0x${value}`]);
}
exports.setBalance = setBalance;

async function startPrank(address) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
}
exports.startPrank = startPrank;

async function stopPrank(address) {
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [address],
  });
}
exports.stopPrank = stopPrank;

const delay = n => new Promise(r => setTimeout(r, n * 1000));
exports.delay = delay;

// This utils function is used to verify contracts on Etherscan and it will do it using
// the built-in hardhat `verify:verify` task or the `hardhat-deploy` `etherscan-verify` task
// depending on the arguments passed to it:
// - `contractName`: the name of the contract to verify
// - `contractAddress`: the address of the contract to verify
// - `constructorArguments`: the constructor arguments of the contract to verify
// - `libraries`: the libraries used by the contract to verify (if any)
// If you want this function to work with the `hardhat-deploy` `ethescan-verify``, you only need to
// pass the `contractName`. Otherwise, you need to pass all the arguments.
exports.verifyOnEtherscan = async (contractName, address, constructorArguments, libraries) => {
  try {
    if (address) {
      await hre.run("verify:verify", {
        contract: contractName,
        address,
        constructorArguments,
        libraries,
      });
    } else {
      // Seems like verifying a contract using the built-in task from hardhat-deploy
      // works well only if we use the param `solcInput` which should not be needed
      // since this was a bug supposedly fixed from Solidity version +0.8
      // (https://github.com/wighawag/hardhat-deploy#4-hardhat-etherscan-verify)
      // Also, verifying contracts when using `hardhat-preprocessor` plugin
      // generates a warning on Etherscan saying that there's a library (__CACHE_BREAKER)
      // that has not been verified. Hence, the lines below are removing this library
      // from the solcInput file (https://github.com/wighawag/hardhat-deploy/issues/78#issuecomment-786914537)

      // Remove __CACHE_BREAKER library from solcInput
      const path = `${__dirname}/deployments/${hre.network.name}/solcInputs`;
      fs.readdirSync(path).forEach(file => {
        var m = JSON.parse(fs.readFileSync(`${path}/${file}`).toString());
        delete m?.settings?.libraries[""]?.__CACHE_BREAKER__;
        fs.writeFileSync(`${path}/${file}`, JSON.stringify(m));
      });

      console.log("Waiting 30 seconds for Etherscan to sync...");
      await delay(30);
      console.log("Trying to verify contract on Etherscan...");
      await hre.run("etherscan-verify", {
        contractName,
        license: "AGPL-3.0",
        forceLicense: true,
        solcInput: true,
      });
    }
  } catch (e) {
    console.log(e);
    console.log("We couldn't verify your contract on Etherscan or it was already verified.");
  }
};

exports.generateTokens = async (tokenAddress, to, amount, signer) => {
  const ERC20_ABI = [
    "function symbol() public view returns (string)",
    "function balanceOf(address) public view returns (uint256)",
  ];
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
  const symbol = await token.symbol();

  // Get storage slot index
  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    [to, this.STORAGE_SLOT[symbol] || 2], // key, slot
  );

  const amt = amount || ethers.utils.parseEther("10000");
  await setStorageAt(
    tokenAddress,
    index.toString(),
    this.toBytes32(amount || ethers.utils.parseEther("10000")).toString(),
  );
  if ((await token.balanceOf(to)).eq(0)) {
    throw new Error(`\n - Failed to generate ${amt} ${symbol} to deployer: ${to}`);
  }
};

// Returns signer using OZ Relayer's API
exports.getRelayerSigner = async () => {
  const { RELAYER_API_KEY: apiKey, RELAYER_API_SECRET: apiSecret } = process.env;
  const provider = new DefenderRelayProvider({ apiKey, apiSecret });
  return new DefenderRelaySigner({ apiKey, apiSecret }, provider, { speed: "fast" });
};

exports.trust = async (token, address) => {
  if (!(await token.isTrusted(address))) {
    await (await token.setIsTrusted(address, true)).wait();
  }
};

exports.approve = async (token, owner, spender) => {
  if ((await token.allowance(owner, spender)).eq(0)) {
    await token.approve(spender, ethers.constants.MaxUint256).then(tx => tx.wait());
  }
};
