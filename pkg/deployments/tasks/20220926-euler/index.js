const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS, VERIFY_CHAINS, EULER, EULER_MARKETS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const factoryAbi = require("./abi/ERC4626Factory.json");
const adapterAbi = [
  "function scale() external view returns (uint256)",
  "function getStakeAndTarget() external view returns (address target, address stake)",
];
const erc20Abi = [
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint256)",
  "function approve(address spender, uint256 amount) public returns (bool)",
];
const eulerMarketsAbi = [
  "function eTokenToUnderlying(address eToken) external view returns (address underlying)",
];

const { verifyOnEtherscan, generateStakeTokens } = require("../../hardhat.utils");

task("20220926-euler", "Deploys Euler 4626 Wrapper Factory and 4626 Euler Vaults").setAction(
  async (_, { ethers }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const chainId = await getChainId();
    const deployerSigner = await ethers.getSigner(deployer);

    if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
    const rewardsRecipient = SENSE_MULTISIG.get(chainId);
    const restrictedAdmin = SENSE_MULTISIG.get(chainId);
    const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

    let deployedVaults = [];

    console.log(`Deploying from ${deployer} on chain ${chainId}`);

    const {
      divider: dividerAddress,
      periphery: peripheryAddress,
      factory: factoryAddress,
      markets,
      series,
    } = data[chainId] || data[CHAINS.MAINNET];
    let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
    let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
    let factory = new ethers.Contract(factoryAddress, factoryAbi, deployerSigner);

    console.log("\n-------------------------------------------------------");
    console.log("\nDeploy Euler Wrapper Factory");
    const { address: wrapperFactoryAddress, abi } = await deploy("EulerERC4626WrapperFactory", {
      from: deployer,
      args: [EULER.get(chainId), EULER_MARKETS.get(chainId), restrictedAdmin, rewardsRecipient],
      log: true,
    });
    const wrapperFactory = new ethers.Contract(wrapperFactoryAddress, abi, deployerSigner);
    console.log(`Euler Wrapper Factory deployed to ${wrapperFactoryAddress}`);
    // if mainnet or goerli, verify on etherscan
    if (VERIFY_CHAINS.includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(wrapperFactoryAddress, [
        EULER.get(chainId),
        EULER_MARKETS.get(chainId),
        restrictedAdmin,
        rewardsRecipient,
      ]);
    }

    console.log("\n-------------------------------------------------------");
    console.log(`\nDeploy Euler 4626 Vaults:`);
    for (const market of markets) {
      const m = new ethers.Contract(market, erc20Abi, deployerSigner);
      const symbol = await m.symbol();

      const eulerMarkets = new ethers.Contract(EULER_MARKETS.get(chainId), eulerMarketsAbi, deployerSigner);
      const underlying = await eulerMarkets.eTokenToUnderlying(market);

      console.log(`\n - Deploy ${symbol} 4626 Wrapper Vault`);
      const vaultAddress = await wrapperFactory.callStatic.createERC4626(underlying);
      await (await wrapperFactory.createERC4626(underlying)).wait();
      deployedVaults.push(vaultAddress);
      console.log(` - ${symbol} 4626 Wrapper Vault deployed to ${vaultAddress}`);

      // if mainnet or goerli, verify on etherscan
      if (VERIFY_CHAINS.includes(chainId)) {
        console.log("\n-------------------------------------------------------");
        await verifyOnEtherscan(vaultAddress, [
          underlying,
          EULER.get(chainId),
          market,
          SENSE_MULTISIG.get(chainId),
        ]);
      }
    }

    // if hardhat fork
    if (chainId == CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");

      // fund multisig
      console.log(`\nFund multisig to be able to make calls from that address`);
      await (
        await deployerSigner.sendTransaction({
          to: senseAdminMultisigAddress,
          value: ethers.utils.parseEther("1"),
        })
      ).wait();

      console.log("\n-------------------------------------------------------");

      // impersonate multisig account
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      periphery = periphery.connect(multisigSigner);
      factory = factory.connect(multisigSigner);

      console.log(`\nWhitelist vaults:`);

      for (let vault of deployedVaults) {
        const v = new ethers.Contract(vault, erc20Abi, deployerSigner);
        console.log(`\n - Add vault ${await v.symbol()} to the whitelist`);
        await (await factory.supportTarget(vault, true)).wait();
      }

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });

      console.log("\n-------------------------------------------------------");
      console.log(`\nDeploy adapters:`);
      for (let vault of deployedVaults) {
        periphery = periphery.connect(deployerSigner);

        vault = new ethers.Contract(vault, erc20Abi, deployerSigner);
        const symbol = await vault.symbol();

        console.log(`\n - Onboard target ${symbol} @ ${vault.address} via factory`);
        const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, vault.address, data);
        await (await periphery.deployAdapter(factoryAddress, vault.address, data)).wait();
        console.log(`  -> ${symbol} adapter address: ${adapterAddress}`);

        console.log(`\n - Can call scale value and check guard amount`);
        const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
        const scale = await adptr.callStatic.scale();
        console.log(`  -> scale: ${scale.toString()}`);

        const params = await await divider.adapterMeta(adapterAddress);
        console.log(
          `  -> adapter guard: ${ethers.utils.formatUnits(
            params[2].toString(),
            await vault.decimals(),
          )} ${symbol}`,
        );

        const { stake } = await adptr.getStakeAndTarget();
        await generateStakeTokens(stake, deployer, deployerSigner);

        console.log(`\n - Prepare to and sponsor series:`);
        console.log(`  * Approve Periphery to pull stake`);
        const stakeContract = new ethers.Contract(stake, erc20Abi, deployerSigner);
        await stakeContract.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        console.log(`  * Mint stake tokens`);

        // deploy Series
        for (let m of series) {
          console.log(`  * Sponsor Series for ${symbol} @ ${vault.address} with maturity ${m}`);
          await periphery.callStatic.sponsorSeries(adapterAddress, m, false);
          await (await periphery.sponsorSeries(adapterAddress, m, false)).wait();
        }
      }
    }

    console.log("\n-------------------------------------------------------");
    console.log(`\nUpdate trusted addresses:`);

    // Unset Euler ERC4626 Wrapper Factory and set multisig as trusted address
    console.log(`\n- Set multisig as trusted address of EulerERC4626WrapperFactory`);
    await (await wrapperFactory.setIsTrusted(wrapperFactoryAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of EulerERC4626WrapperFactory`);
    await (await wrapperFactory.setIsTrusted(deployer, false)).wait();

    if (VERIFY_CHAINS.includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
      console.log("\n1. Support targets (vaults) on 4626 factory");
      console.log("\n2. Deploy adapters on Periphery (for each vault)");
      console.log("\n2. For each adapter, sponsor Series on Periphery");
      console.log("\n3. For each series, run capital seeder");
    }
  },
);
