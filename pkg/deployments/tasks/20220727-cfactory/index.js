const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const { SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task(
  "20220727-cfactory",
  "Deploys a new Compound Factory and adds it to the Periphery",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let divider = new ethers.Contract(mainnet.divider, dividerAbi, deployerSigner);
  let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, deployerSigner);

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
      targets,
      reward,
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
        tilt
      })}}`,
    );
    const factoryParams = [oracle, stake, stakeSize, minm, maxm, ifee, mode, tilt];
    const { address: factoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });
      
    console.log(`${factoryContractName} deployed to ${factoryAddress}`);
    
    // if not hardhat fork, we try verifying on etherscan    
    if (chainId === CHAINS.HARDHAT) {      
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(factoryAddress, [divider.address, factoryParams, reward]);
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

      console.log(`\nAdd ${factoryContractName} as trusted address of Divider`);
      await (await divider.setIsTrusted(factoryAddress, true)).wait();
      
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    

      console.log("\n-------------------------------------------------------");
      console.log(`Deploy adapters for: ${factoryContractName}`);
      for (let t of targets) {
        periphery = periphery.connect(deployerSigner);
        
        console.log(`\nOnboard target ${t.name} @ ${t.address} via Factory ${factoryContractName}`);
        const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address, 0x0);
        await (await periphery.deployAdapter(factoryAddress, t.address, 0x0)).wait();
        console.log(`${t.name} adapter address: ${adapterAddress}`);

        console.log(`Can call scale value`);
        const ADAPTER_ABI = [ "function scale() public returns (uint256)" ];        
        const adptr = new ethers.Contract(adapterAddress, ADAPTER_ABI, deployerSigner);
        const scale = await adptr.callStatic.scale();
        console.log(`-> scale: ${scale.toString()}`);

        const params = await divider.callStatic.adapterMeta(adapterAddress);
        console.log(`Adapter guard: ${params[2]}`);
      }
    }

    if (chainId === CHAINS.MAINNET) {
      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
      console.log("\n1. Set factory on Periphery");
      console.log("\n2. Deploy adapters on Periphery (if needed)");
      console.log("\n3. For each adapter, sponsor Series on Periphery");
      console.log("\n4. For each series, run capital seeder");
    }

  }

});
