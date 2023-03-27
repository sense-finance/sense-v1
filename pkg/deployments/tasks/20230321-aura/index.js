const { task } = require("hardhat/config");
const data = require("./input");

const {
  SENSE_MULTISIG,
  CHAINS,
  VERIFY_CHAINS,
  WETH_TOKEN,
  auraB_rETH_STABLE_vault,
} = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const rlvFactoryAbi = require("./abi/AutoRollerFactory.json");
const rlvAbi = require("./abi/AutoRoller.json");
const ERC20_ABI = ["function approve(address spender, uint256 amount) public returns (bool)"];
const ChainlinkOracleAbi = [
  "function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
];
const ETH_USD_PRICEFEED = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"; // Chainlink ETH-USD price feed

const {
  verifyOnEtherscan,
  setBalance,
  stopPrank,
  startPrank,
  generateTokens,
  decimalToPercentage,
} = require("../../hardhat.utils");

task(
  "20230321-aura",
  "Deploys an Aura Vault Wrapper for auraB-rETH-WETH-STABLE-vault and deploys an Ownable Aura Adapter & tests deploying an RLV and rolling",
).setAction(async (_, { ethers }) => {
  const _deployAdapter = async (divider, target) => {
    console.log("\n-------------------------------------------------------");
    console.log("Deploy Ownable Aura Adapter for %s", await target.name());
    console.log("-------------------------------------------------------\n");

    const {
      contractName,
      contract,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
      level,
      rewardTokens,
      guard,
    } = adapterArgs;

    const adapterParams = [masterOracleAddress, stake, stakeSize, minm, maxm, tilt, level, mode];

    console.log(
      `Adapter Params: ${JSON.stringify({
        oracle: masterOracleAddress,
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        tilt,
        level,
        mode,
      })}}`,
    );
    console.log(
      `Adapter ifee: ${ifee.toString()} (${decimalToPercentage(ethers.utils.formatEther(ifee.toString()))}%)`,
    );
    console.log(`Reward tokens: ${rewardTokens}\n`);

    const { address: adapterAddress, abi } = await deploy(contractName, {
      contract: contract || contractName,
      from: deployer,
      args: [divider.address, target.address, rewardsRecipient, ifee, adapterParams, rewardTokens],
      log: true,
      // gasPrice: 28000000000,
    });
    const adapter = new ethers.Contract(adapterAddress, abi, deployerSigner);

    console.log(`- Set rlvFactory as trusted address of adapter`);
    await (await adapter.setIsTrusted(rlvFactory.address, true)).wait();

    if (chainId === CHAINS.HARDHAT) {
      startPrank(senseAdminMultisigAddress);
      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
    }

    console.log(`- Set guard`);
    const ethPrice = (
      await new ethers.Contract(ETH_USD_PRICEFEED, ChainlinkOracleAbi, deployerSigner).latestRoundData()
    ).answer;
    const ethPriceScaled = ethers.utils.parseUnits(ethPrice.toString(), 10);
    const guardInEth = ethers.utils.parseEther(guard.div(ethPriceScaled).toString());
    await (await divider.setGuard(adapter.address, guardInEth)).wait();

    if (chainId === CHAINS.HARDHAT) {
      stopPrank(senseAdminMultisigAddress);
      divider = divider.connect(deployerSigner);
    }

    console.log(`- Can call scale value`);
    const scale = await adapter.callStatic.scale();
    console.log(`  -> scale: ${scale.toString()}`);

    const params = await await divider.adapterMeta(adapterAddress);
    console.log(`  -> adapter guard: ${params[2]}`);

    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(contractName);
    }

    console.log(`${contractName} deployed to ${adapterAddress}`);
    return adapter;
  };

  const _deployWrapper = async () => {
    console.log("-------------------------------------------------------");
    console.log("Deploy Aura Vault Wrapper");
    console.log("-------------------------------------------------------");
    const { address: targetAddress, abi } = await deploy("AuraVaultWrapper", {
      from: deployer,
      args: [WETH_TOKEN.get(chainId), auraB_rETH_STABLE_vault.get(chainId)],
      log: true,
      // gasPrice: 28000000000,
    });

    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan("AuraVaultWrapper");
    }

    console.log(`AuraVaultWrapper deployed to ${targetAddress}\n`);
    return new ethers.Contract(targetAddress, abi, deployerSigner);
  };

  const _deployRLV = async (adapter, rlvFactory, rewardTokens) => {
    console.log(`\nDeploy multi rewards distributor with reward tokens: ${rewardTokens}`);
    const { address: rdAddress } = await deploy("MultiRewardsDistributor", {
      from: deployer,
      args: [rewardTokens],
      log: true,
      // gasPrice: 28000000000,
    });
    console.log("- Rewards distributor deployed @ %s", rdAddress);

    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan("RewardsDistributor");
    }

    // create RLV
    console.log("\n-------------------------------------------------------");
    console.log("Create RLV for %s", await adapter.name());
    console.log("-------------------------------------------------------\n");
    const rlvAddress = await rlvFactory.callStatic.create(adapter.address, adapterArgs.rewardsRecipient, 3);
    await (await rlvFactory.create(adapter.address, adapterArgs.rewardsRecipient, 3)).wait();
    const rlv = new ethers.Contract(rlvAddress, rlvAbi, deployerSigner);
    console.log("- RLV %s deployed @ %s", await rlv.name(), rlvAddress);
    return rlv;
  };

  const _roll = async (target, stake, stakeSize, rlv) => {
    // approve RLV to pull target
    await (await target.approve(rlv.address, ethers.utils.parseEther("2"))).wait();

    // approve RLV to pull stake
    await (await stake.approve(rlv.address, stakeSize)).wait();

    // load wallet with stake
    await generateTokens(stake.address, deployer, deployerSigner, stakeSize);

    // load wallet with BPTs
    const pool = await target.pool();
    await generateTokens(pool, deployer, deployerSigner, ethers.utils.parseEther("10"));

    // approve target to pull target's BPT
    const bpt = new ethers.Contract(pool, ERC20_ABI, deployerSigner);
    await (await bpt.approve(target.address, ethers.constants.MaxUint256)).wait();

    // wrap BPT into target
    await (await target.depositFromBPT(ethers.utils.parseEther("10"), deployer)).wait();

    // roll 1st series
    await (await rlv.roll()).wait();
    console.log("- First series sucessfully rolled!");

    // check we can deposit
    await (await rlv.deposit(ethers.utils.parseEther("1"), deployer)).wait(); // deposit 1 target
    console.log("- 1 target sucessfully deposited!");
  };

  const _onboardAdapter = async () => {
    if (chainId !== CHAINS.MAINNET) {
      if (chainId === CHAINS.HARDHAT) {
        startPrank(senseAdminMultisigAddress);
        const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
        periphery = periphery.connect(multisigSigner);
      }

      console.log(`- Onboard ${await adapter.name()} adapter`);
      await (await periphery.onboardAdapter(adapter.address, true)).wait();

      if (chainId === CHAINS.HARDHAT) {
        stopPrank(senseAdminMultisigAddress);
        periphery = periphery.connect(deployerSigner);
      }
    }
  };

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);
  const {
    divider: dividerAddress,
    periphery: peripheryAddress,
    rewardsRecipient,
    oracle: masterOracleAddress,
    adapterArgs,
    rlvFactory: rlvFactoryAddress,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);
  let rlvFactory = new ethers.Contract(rlvFactoryAddress, rlvFactoryAbi, deployerSigner);

  // Fund multisig if deploying on fork
  if (chainId === CHAINS.HARDHAT) {
    console.log(`- Fund multisig to be able to make calls from that address`);
    await setBalance(senseAdminMultisigAddress, ethers.utils.parseEther("1").toString());
  }

  const wrapper = await _deployWrapper();
  const adapter = await _deployAdapter(divider, wrapper);
  await _onboardAdapter();

  const rlv = await _deployRLV(adapter, rlvFactory, adapterArgs.rewardTokens);

  if (chainId !== CHAINS.MAINNET) {
    // roll first series
    const stake = new ethers.Contract(adapterArgs.stake, ERC20_ABI, deployerSigner);
    await _roll(wrapper, stake, adapterArgs.stakeSize, rlv);
  }

  console.log("\n-------------------------------------------------------");

  if (deployer.toUpperCase() !== senseAdminMultisigAddress.toUpperCase()) {
    // Unset deployer and set multisig as trusted address

    console.log(`\n- Set multisig as trusted address of Wrapper`);
    await (await wrapper.setIsTrusted(senseAdminMultisigAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of Wrapper`);
    await (await wrapper.setIsTrusted(deployer, false)).wait();

    console.log(`\n- Set multisig as trusted address of Adapter`);
    await (await adapter.setIsTrusted(senseAdminMultisigAddress, true)).wait();

    console.log(`- Unset deployer as trusted address of Adapter`);
    await (await adapter.setIsTrusted(deployer, false)).wait();
  }

  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("-------------------------------------------------------");
    console.log("ACTIONS TO BE DONE ON DEFENDER: ");
    console.log("1. Onboard adapter via periphery.onboardAdapter (multisig)");
    console.log("2. Set guard on adapter via divider.setGuard (multisig)");
    console.log("3. Roll series (defender or other)");
  }
});
