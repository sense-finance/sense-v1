const fs = require("fs-extra");
const path = require("path");
const { exec } = require("child_process");
const log = console.log;
const { DefenderRelayProvider, DefenderRelaySigner } = require("defender-relay-client/lib/ethers");
const { SignatureTransfer } = require("@uniswap/permit2-sdk");
const { ETH_TOKEN, CHAINS } = require("./hardhat.addresses");

// More info here (https://kndrck.co/posts/local_erc20_bal_mani_w_hh/)
exports.STORAGE_SLOT = {
  DAI: 2,
  stETH: 0,
  wstETH: 0,
  WETH: 3,
  USDC: 9,
  maDAI: 51,
  maUSDC: 51,
  maUSDT: 51,
  FRAX: 0,
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

exports.generateTokens = async (tokenAddress, to, signer, amt) => {
  const { abi: tokenAbi } = await deployments.getArtifact("Token");
  const token = new ethers.Contract(tokenAddress, tokenAbi, signer);
  const symbol = await token.symbol();

  // Get storage slot index
  const slot = this.STORAGE_SLOT[symbol];
  const index = ethers.utils.solidityKeccak256(
    ["uint256", "uint256"],
    [to, typeof slot === "undefined" ? 2 : slot], // key, slot
  );

  await setStorageAt(
    tokenAddress,
    index.toString(),
    this.toBytes32(amt || ethers.utils.parseEther("10000000")).toString(),
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

// receives desired percentage and returns the decimal value
// e.g 0.05% will return 0.0005
exports.percentageToDecimal = percentage => percentage / 100;
exports.decimalToPercentage = percentage => percentage * 100;

// receives desired percentage and returns the bps value
// e.g 0.05% will return 5
exports.bpsToDecimal = percentage => percentage * 100;
exports.decimalToBps = percentage => percentage / 100;

// TODO: is there any better way to calculate nonces? should I use last transaction and have ordered nonces?
exports.generatePermit = async (token, amount, spender, permit2, chainId, signer) => {
  const block = await ethers.provider.getBlock("latest");
  const deadline = block.timestamp + 20; // 20 seconds
  // const nonce = (await permit2.allowance(signer.address, token, spender)).nonce;
  // const nonce = await signer.getTransactionCount(signer.address);
  let nonce = Math.floor(Math.random() * 1000);
  // let nonceBitmap = await permit2.nonceBitmap(signer.address, nonce);
  // console.log("Nonce", nonce);
  // console.log("Nonce bitmap", nonceBitmap);
  // console.log("Nonce from allowance", (await permit2.allowance(signer.address, token, spender)).nonce)
  // console.log("Nonce expiration", (await permit2.allowance(signer.address, token, spender)).expiration)
  const message = {
    permitted: {
      token,
      amount,
    },
    nonce,
    deadline,
  };

  const { domain, types, values } = SignatureTransfer.getPermitData(
    { ...message, spender },
    permit2.address,
    chainId,
  );
  const signature = await signer._signTypedData(domain, types, values);
  return [signature, message];
};

// Get a quote from 0x-API to sell the WETH we just deposited into the contract.
exports.getQuote = async (sellTokenAddr, buyTokenAddr, sellAmount) => {
  const { abi: tokenAbi } = await deployments.getArtifact("Token");
  const sellToken = new ethers.Contract(sellTokenAddr, tokenAbi, ethers.provider);
  const buyToken = new ethers.Contract(buyTokenAddr, tokenAbi, ethers.provider);
  const sellETH = sellTokenAddr === ETH_TOKEN.get(CHAINS.MAINNET);
  const buyETH = buyTokenAddr === ETH_TOKEN.get(CHAINS.MAINNET);

  // let decimals = 18;
  // if (!sellETH) decimals = await sellToken.decimals();
  // amt = ethers.utils.parseEther(amt, decimals);

  console.info(
    ` - Fetch swap quote from 0x-API to sell ${ethers.utils.formatEther(sellAmount)} ${
      sellETH ? "ETH" : await sellToken.symbol()
    } for ${buyETH ? "ETH" : await buyToken.symbol()}...`,
  );
  const qs = createQueryString({
    sellToken: sellToken.address,
    buyToken: buyToken.address,
    sellAmount,
  });
  const API_QUOTE_URL = "https://api.0x.org/swap/v1/quote";
  const quoteUrl = `${API_QUOTE_URL}?${qs}`;
  console.info(`  * Fetching quote ${quoteUrl}...`);
  const response = await fetch(quoteUrl);
  const quote = await response.json();
  console.info(`  * Received a quote with price ${quote.price}`);
  return quote;
};

const createQueryString = params => {
  return Object.entries(params)
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
};

// utils
const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
exports.ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;

exports.one = decimals => ethers.utils.parseUnits("1", decimals);
exports.oneHundred = decimals => ethers.utils.parseUnits("100", decimals);
exports.fourtyThousand = decimals => ethers.utils.parseUnits("40000", decimals);
exports.oneMillion = decimals => ethers.utils.parseUnits("1000000", decimals);
exports.tenMillion = decimals => ethers.utils.parseUnits("10000000", decimals);

exports.zeroAddress = () => ethers.constants.AddressZero;
