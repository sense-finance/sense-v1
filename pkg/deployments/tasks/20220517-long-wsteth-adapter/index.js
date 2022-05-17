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

const { SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");

task(
  "20220517-long-wsteth-adapter",
  "Deploys long term wstETH adapter",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
  let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

  console.log("\n-------------------------------------------------------");

  for (let adapter of mainnet.adapters) {
    const { contractName, deploymentParams, target } = adapter;
    const { underlying, ifee, adapterParams } = deploymentParams;

    console.log(`\nDeploy ${contractName}`);
    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, target.address, underlying, ifee, [...Object.values(adapterParams)]],
      log: true,
    });
    console.log(`${contractName} adapter deployed at ${adapterAddress}`);

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
    console.log(`${contractName} adapterAddress: ${adapterAddress}`);
  }
});
