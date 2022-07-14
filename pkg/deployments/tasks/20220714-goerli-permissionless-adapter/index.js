const { task } = require("hardhat/config");
const { goerli } = require("./input");

const peripheryAbi = require("./abi/Periphery.json");
const dividerAbi = require("./abi/Divider.json");
const targetAbi = require("./abi/Target.json");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task(
  "20220714-goerli-permissionless-adapter",
  "Turns permissionless mode and deploys adapter perrmissionlessly (only forr Goerli)",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (chainId === "5") {
    console.log("\n-------------------------------------------------------");
    console.log(`\nChain is ${chainId}`);

    const periphery = new ethers.Contract(goerli.periphery, peripheryAbi, deployerSigner);
    const divider = new ethers.Contract(goerli.divider, dividerAbi, deployerSigner);

    if (!await divider.permissionless()) {
      console.log(`\nTurn on permissionless mode...`);
      await (await divider.setPermissionless(true)).wait();
    } else {
      console.log(`\nPermissionless mode already on`);
    }

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy adapters permissionlessly`);
    for (let adapter of goerli.adapters) {
      let {
        contractName,
        divider,
        target,
        ifee,
        adapterParams,
        reward,
      } = adapter;

      target = new ethers.Contract(target, targetAbi, deployerSigner);
      adapterParams = Object.values(adapterParams);
      const targetSymbol = await target.symbol();
      console.log(
        `\nDeploy ${targetSymbol} ${contractName} with params ${JSON.stringify(adapter)}}`,
      );
      const { address: adapterAddress } = await deploy(contractName, {
        from: deployer,
        args: [divider, target.address, await target.underlying(), ifee, adapterParams, reward],
        log: true,
      });
      console.log(`${targetSymbol} ${contractName} deployed to ${adapterAddress}`);

      console.log(`Can call scale value`);
      const ADAPTER_ABI = [ "function scale() public returns (uint256)" ];        
      const adptr = new ethers.Contract(adapterAddress, ADAPTER_ABI, deployerSigner);
      const scale = await adptr.callStatic.scale();
      console.log(`-> scale: ${scale.toString()}`);

      console.log(`\Onboard ${contractName} into Divider permissionlessly via Periphery`);
      if (!await periphery.isTrusted(deployer)) {
        await (await periphery.onboardAdapter(adapterAddress, true)).wait();
      } else {
        throw Error("You are trying to onboard the adapter with the trusted address. Try it out with a non trusted address.")
      }

      console.log("\n-------------------------------------------------------");
      console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
      console.log("\n1. Set guard to max uint so we don't have to worry about it");

      // verify adapter contract on etherscan
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(adapterAddress, [divider, target.address, await target.underlying(), ifee, adapterParams, reward]);
    }
  }

});
