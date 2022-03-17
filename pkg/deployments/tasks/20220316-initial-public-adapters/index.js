const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

const { BALANCER_VAULT, SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const poolMangerAbi = require("./abi/PoolManager.json");

const ADAPTER_ABI = [
  "function stake() public view returns (address)",
  "function stakeSize() public view returns (uint256)",
];

task(
  "20220316-initial-public-adapters",
  "Deploys, configures, and initialized liquidity for the first public Seires",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
  let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);
  let poolManager = new ethers.Contract(mainnet.poolManager, poolMangerAbi, signer);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (let factory of mainnet.factories) {
    const {
      contractName: factoryContractName,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      oracle,
      tilt,
      reward,
      targets,
    } = factory;
    console.log(
      `\nDeploy ${factoryContractName} with params ${JSON.stringify({
        ifee: ifee.toString(),
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle,
        tilt,
        reward,
      })}}`,
    );
    const factoryParams = [oracle, ifee, stake, stakeSize, minm, maxm, mode, tilt];
    const { address: factoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });

    console.log(`${factoryContractName} deployed to ${factoryAddress}`);

    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
      periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

      console.log(`\nTrust ${factoryContractName} on the divider`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();

      console.log(`\nAdd ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    }

    divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy adapters for: ${factoryContractName}`);
    for (let t of targets) {
      if (chainId === "111") {
        console.log("\n-------------------------------------------------------");
        console.log("Checking multisig txs by impersonating the address");

        if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
        const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
        await hre.network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [senseAdminMultisigAddress],
        });
        const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

        console.log(`\nOnboard target ${t.name} @ ${t.address} via Factory ${factoryContractName}`);

        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address);
        await (await periphery.deployAdapter(factoryAddress, t.address)).wait();

        divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
        console.log(`\nSet ${t.name} adapter issuance cap to ${t.guard}`);
        await divider.setGuard(adapterAddress, t.guard).then(tx => tx.wait());

        await hre.network.provider.request({
          method: "hardhat_stopImpersonatingAccount",
          params: [senseAdminMultisigAddress],
        });
      }

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    }
  }

  for (let adapter of mainnet.adapters) {
    const { contractName, deploymentParams, target } = adapter;

    console.log(`\nDeploy ${contractName}`);
    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, ...Object.values(deploymentParams)],
      log: true,
    });

    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
      periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

      console.log(`Set ${contractName} adapter issuance cap to ${target.guard}`);
      await divider.setGuard(adapterAddress, target.guard).then(tx => tx.wait());

      console.log(`Verify ${contractName} adapter`);
      await periphery.verifyAdapter(adapterAddress, false).then(tx => tx.wait());

      console.log(`Onboard ${contractName} adapter`);
      await periphery.onboardAdapter(adapterAddress, true).then(tx => tx.wait());

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    }
    divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

    console.log(`Can call scale value`);
    const { abi: adapterAbi } = await deployments.getArtifact(contractName);
    const adptr = new ethers.Contract(adapterAddress, adapterAbi, signer);
    const scale = await adptr.callStatic.scale();
    console.log(`-> scale: ${scale.toString()}`);

    const { name: targetName, series, address: targetAddress } = target;
    const { abi: tokenAbi } = await deployments.getArtifact("Token");
    const targetContract = new ethers.Contract(targetAddress, tokenAbi, signer);

    console.log("\nEnable the Divider to move the deployer's Target for issuance");
    await targetContract.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapterAddress, ADAPTER_ABI, signer);

      console.log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
      const stakeAddress = await adapter.stake();
      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
      await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const stakeSize = await adapter.stakeSize();
      const balance = await stake.balanceOf(deployer);
      if (balance.lt(stakeSize)) {
        throw Error("Not enough stake funds on wallet");
      }
      console.log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      console.log(await periphery.callStatic.sponsorSeries(adapter.address, seriesMaturity, true));
      await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());
      console.log("\n-------------------------------------------------------");
    }
  }

  // add liquidity at initial price
});
