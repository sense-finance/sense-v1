const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { BALANCER_VAULT, SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");

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
    // Large enough to not be a problem, but won't overflow on ModAdapter.fmul
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

      console.log(`Trust ${factoryContractName} on the divider`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();

      console.log(`Add ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();
    }

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy adapters for: ${factoryContractName}`);
    for (let t of targets) {
      console.log(`\nOnboard target ${t.name} via Periphery`);
      await (await periphery.deployAdapter(factoryAddress, t.address)).wait();
    }
  }

  // deploy adapter
  // deploy adapter factory
  // deploy adapter
  // set guard
  // sponosr series
  // add liquidity at initial price
});
