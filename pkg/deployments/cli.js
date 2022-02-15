// Hardhat tasks for interacting with deployed contracts
// Usage: npx hardhat <task> --arg <value>

const { task } = require("hardhat/config");
const fs = require("fs");
const dayjs = require("dayjs");
const { NonceManager } = require("@ethersproject/experimental");

const utc = require("dayjs/plugin/utc");
const weekOfYear = require("dayjs/plugin/weekOfYear");

dayjs.extend(weekOfYear);
dayjs.extend(utc);

task("accounts", "Prints the list of accounts", async (_, { ethers }) => {
  const signers = await ethers.getSigners();

  for (const signer of signers) {
    console.log(signer.address);
  }
});

task("localhost-faucet", "Sends the provided address ETH and Target")
  .addParam("port", "The port number to run against")
  .addParam("contractsPath", "Path to the deployed contract export data")
  .addParam("address", "The account's address")
  .setAction(async ({ address, port, contractsPath }, { ethers }) => {
    console.log(contractsPath, "contractPath");
    const deployment = JSON.parse(fs.readFileSync(`${contractsPath}`, "utf8"));
    const { contracts } = deployment;

    if (!contracts) {
      throw new Error("Unable to find contracts at given path");
    }

    const testchainProvider = new ethers.providers.JsonRpcProvider(`http://localhost:${port}/`);
    const signer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC).connect(testchainProvider);

    const ethToTransfer = ethers.utils.parseEther("5");

    console.log(`Transferring ${ethToTransfer} ETH to ${address}`);
    await signer
      .sendTransaction({
        to: address,
        value: ethToTransfer,
      })
      .then(tx => tx.wait());

    const targetToMint = ethers.utils.parseEther("100");

    for (let targetName of global.TARGETS) {
      const tokenContract = new ethers.Contract(
        contracts[targetName].address,
        ["function mint(address,uint256) external"],
        signer,
      );

      console.log(`Minting ${targetToMint} ${targetName} to ${address}`);
      await tokenContract.mint(address, targetToMint).then(tx => tx.wait());
    }
  });

task("init-series", "Init Series").setAction(async (_, { ethers }) => {
  const DIVIDER_GOERLI = "0x7203BF9B8C163f5f5502245aD75BAa6785653260";
  const BALANCER_VAULT_GOERLI = "0x9B0CCe02356B8DE1F66F07dEA5c51932133c90f8";

  const deployer = "0xF13519734649F7464E5BE4aa91987A35594b2B16";

  const testchainProvider = new ethers.providers.InfuraProvider("goerli", "19eab106ef8b4469ad8ed01947698acf");
  const signer = new NonceManager(ethers.Wallet.fromMnemonic(process.env.MNEMONIC).connect(testchainProvider));

  const deployment = JSON.parse(fs.readFileSync(`./exports/localhost`, "utf8"));
  const { contracts } = deployment;

  const divider = new ethers.Contract(DIVIDER_GOERLI, contracts.Divider.abi, signer);
  const periphery = new ethers.Contract(
    await divider.periphery(),
    JSON.parse(fs.readFileSync(`./abi/@sense-finance/v1-core/src/Periphery.sol/Periphery.json`, "utf8")),
    signer,
  );

  const balancerVault = new ethers.Contract(
    BALANCER_VAULT_GOERLI,
    JSON.parse(fs.readFileSync(`./abi/@balancer-labs/v2-vault/contracts/Vault.sol/Vault.json`, "utf8")),
    signer,
  );
  const spaceFactory = new ethers.Contract(
    await periphery.spaceFactory(),
    ["function pools(address,uint256) external view returns (address)"],
    signer,
  );

  const initialised = await divider.queryFilter(divider.filters.SeriesInitialized(null, null, null, null, null, null));
  const adapterAddresses = [...new Set(initialised.map(log => log.args.adapter))];

  // const underlyings = [
  //   ...new Set(
  //     await Promise.all(
  //       targetAddresses.map(targetAddress =>
  //         new ethers.Contract(
  //           targetAddress,
  //           ["function underlying() external view returns (address)"],
  //           signer,
  //         ).underlying(),
  //       ),
  //     ),
  //   ),
  // ];

  const maturities = [
    // beginning of the week falling between 0 and 1 weeks from now
    dayjs
      .utc()
      .week(dayjs().week() + 2)
      .startOf("week")
      .add(1, "day")
      .unix(),
    // beginning of the week falling between 1 and 2 weeks from now
    // dayjs
    //   .utc()
    //   .week(dayjs().week() + 2)
    //   .startOf("week")
    //   .add(1, "day")
    //   .unix(),
  ];

  for (let adapterAddress of adapterAddresses) {
    for (let maturity of maturities) {
      console.log(`Initializing Series maturing on ${dayjs(maturity * 1000)} for ${adapterAddress}`);
      const adapter = new ethers.Contract(
        adapterAddress,
        JSON.parse(
          fs.readFileSync(`./abi/@sense-finance/v1-core/src/adapters/BaseAdapter.sol/BaseAdapter.json`, "utf8"),
        ),
        signer,
      );

      const targetAddress = await adapter.target();
      const target = new ethers.Contract(
        targetAddress,
        [
          "function approve(address,uint256) external",
          "function symbol() external view returns (string)",
          "function balanceOf(address) external view returns (uint256)",
          "function mint(address,uint256) external",
        ],
        signer,
      );

      console.log("Have the deployer issue the first 1,000,000 Target worth of Zeros/Claims for this Series");
      // try {
      //   await periphery.sponsorSeries(adapterAddress, maturity);
      //   await target.mint(deployer, ethers.utils.parseEther("10000000")).then(tx => tx.wait());
      //   await divider.issue(adapterAddress, maturity, ethers.utils.parseEther("1000000")).then(tx => tx.wait());
      //   console.error("try init");
      // } catch (err) {
      //   console.error("error init");
      // }

      console.log("succeeded in initializing Series");

      const { zero: zeroAddress, claim: claimAddress } = await divider.series(adapterAddress, maturity);

      const zero = new ethers.Contract(
        zeroAddress,
        ["function approve(address,uint256) external", "function balanceOf(address) external view returns (uint256)"],
        signer,
      );
      const claim = new ethers.Contract(claimAddress, ["function approve(address,uint256) external"], signer);

      const symbol = await target.symbol();
      if (symbol !== "cDAI" && symbol !== "cETH") {
        continue;
      }

      console.log(symbol, "adding liq");
      const poolAddress = await spaceFactory.pools(adapterAddress, maturity);
      const pool = new ethers.Contract(
        poolAddress,
        [
          "function getPoolId() external view returns (bytes32)",
          "function getIndices() external view returns (uint8 _zeroi, uint8 _targeti)",
        ],
        signer,
      );
      const poolId = await pool.getPoolId();

      const { tokens, balances } = await balancerVault.getPoolTokens(poolId);

      console.log(poolId, tokens, balances, zeroAddress, "tokens balances");

      console.log("Sending Zeros to mock Balancer Vault");
      try {
        await zero.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        console.log("zero balance", await zero.balanceOf(deployer).then(b => b.toString()));
        console.log("target balance", await target.balanceOf(deployer).then(b => b.toString()));
        console.log("zero target", zero.address, target.address);
        console.log("pool tokens", tokens[0], tokens[1]);
        console.log("pool balances", ethers.utils.formatEther(balances[0]), ethers.utils.formatEther(balances[1]));
        await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        const { defaultAbiCoder } = ethers.utils;

        const { _zeroi, _targeti } = await pool.getIndices();
        const initialBalances = [null, null];
        initialBalances[_zeroi] = ethers.utils.parseEther("100000");
        initialBalances[_targeti] = ethers.utils.parseEther("100000");

        // const userData = defaultAbiCoder.encode(["uint[]"], [initialBalances]);
        // await balancerVault
        //   .joinPool(poolId, deployer, deployer, {
        //     assets: tokens,
        //     maxAmountsIn: [ethers.constants.MaxUint256, ethers.constants.MaxUint256],
        //     fromInternalBalance: false,
        //     userData,
        //   })
        //   .then(tx => tx.wait());

        console.log("Making swap to init Zeros");
        await balancerVault
          .swap(
            {
              poolId,
              kind: 0, // given in
              assetIn: target.address,
              assetOut: zero.address,
              amount: ethers.utils.parseEther("75002"),
              userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
            },
            { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
            0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
            ethers.constants.MaxUint256, // `deadline` – no deadline
          )
          .then(tx => tx.wait());
        console.log("succeeded in adding liq");
      } catch (er) {
        console.log("failed to add liq", er);
      }
    }
  }
});
