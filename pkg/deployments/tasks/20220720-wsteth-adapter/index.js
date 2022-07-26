const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task(
  "20220720-wsteth-adapter",
  "Deploys wstETH adapter (with stETH as underlying)",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  let divider = new ethers.Contract(mainnet.divider, dividerAbi);
  let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);
  console.log("\n-------------------------------------------------------");

  for (let adapter of mainnet.adapters) {
    const { contractName, deploymentParams, target } = adapter;
    const { ifee, adapterParams } = deploymentParams;
    
    divider = divider.connect(deployerSigner);
    periphery = periphery.connect(deployerSigner);

    console.log(`\nDeploy ${contractName}`);
    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, target.address, ifee, [...Object.values(adapterParams)]],
      log: true,
    });
    console.log(`${contractName} adapter deployed at ${adapterAddress}`);

    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No multisig found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      divider = divider.connect(multisigSigner);
      periphery = periphery.connect(multisigSigner);

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

    console.log(`Can call scale value`);
    const { abi: adapterAbi } = await deployments.getArtifact(contractName);
    const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
    const scale = await adptr.callStatic.scale();
    console.log(`-> scale: ${scale.toString()}`);

    console.log("\n-------------------------------------------------------");
    console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
    console.log("\n1. Set guard to 500 ETH on Divider");
    console.log("\n2. Verify adapter on Periphery");
    console.log("\n3. Onboard adapter on Periphery");

    // verify adapter contract on etherscan
    if (chainId !== "111") {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan("0x29872d0a2672bA73D540c53330E1A073c3cE2673", [divider.address, target.address, ifee, adapterParams]);
    }
  }
});
