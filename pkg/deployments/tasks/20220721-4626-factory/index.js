const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task(
  "20220721-4626-factory",
  "Deploys 4626 Factory and adds it to the Periphery. Also deploys Sense Master & Chainlink Oracles",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  const { divider: dividerAddress, periphery: peripheryAddress, factories, maxSecondsBeforePriceIsStale } = data[chainId] || data[CHAINS.MAINNET];
  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Sense Chainlink Price Oracle");
  const { address: chainlinkOracleAddress } = await deploy("ChainlinkPriceOracle", {
    from: deployer,
    args: [maxSecondsBeforePriceIsStale],
    log: true,
  });

  // if mainnet or goerli, verify on etherscan
  if ([CHAINS.MAINNET, CHAINS.GOERLI].includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(chainlinkOracleAddress, [maxSecondsBeforePriceIsStale]);
  }

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Sense Master Price Oracle");
  const { address: masterOracleAddress } = await deploy("MasterPriceOracle", {
    from: deployer,
    args: [chainlinkOracleAddress, [], []],
    log: true,
  });

  // if mainnet or goerli, verify on etherscan
  if ([CHAINS.MAINNET, CHAINS.GOERLI].includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(masterOracleAddress, [chainlinkOracleAddress, [], []]);
  }

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (let factory of factories) {
    const {
      contractName: factoryContractName,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      tilt,
    } = factory;

    console.log(
      `\nDeploy ${factoryContractName} with params ${JSON.stringify({
        ifee: ifee.toString(),
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle: masterOracleAddress,
        tilt
      })}}`,
    );
    const factoryParams = [masterOracleAddress, stake, stakeSize, minm, maxm, ifee, mode, tilt];
    const { address: factoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams],
      log: true,
    });

    console.log(`${factoryContractName} deployed to ${factoryAddress}`);

    // if not hardhat fork, we try verifying on etherscan
    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(factoryAddress, [divider.address, factoryParams]);
    } else {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

      console.log(`\nAdd ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    }

    if ([CHAINS.MAINNET, CHAINS.GOERLI].includes(chainId)) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
      console.log("\n1. Set factory on Periphery");
    }

  }

});
