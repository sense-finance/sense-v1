const { DefenderRelayProvider, DefenderRelaySigner } = require('defender-relay-client/lib/ethers');
const { ethers } = require('ethers');

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
  const { deployer } = await getNamedAccounts();
  const deployerSigner = await ethers.getSigner(deployer);

  console.log(`Can call scale value`);
  const { abi: adapterAbi } = await deployments.getArtifact("WstETHAdapter");
  const adapterAddress = "0x6fC4843aac4786b4420e954a2271BE16f225a482";
  const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
  const scale = await adptr.callStatic.scale();
  console.log(`-> scale: ${scale.toString()}`);

  const relayer = "0xe09fe5acb74c1d98507f87494cf6adebd3b26b1e";
  // await hre.network.provider.request({
  //   method: "hardhat_impersonateAccount",
  //   params: [relayer],
  // });
  // const signer = await hre.ethers.getSigner(relayer);
  const credentials = { apiKey: "VPwQ7wVktv4Vf6xEm9gUoTLPVfM5TjTN", apiSecret: "t58sRtcWmcKcrPHc2ocG5af2d9YD1rnNhMRRwt7e7Q4xDjXd3dPzYx5uKFdJ8pKt" };
  const provider = new DefenderRelayProvider(credentials);
  const signer = new DefenderRelaySigner(credentials, provider, { speed: 'fast' });

  const periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);
  const seriesMaturity = 1811808000;
  console.log(`\nInitializing Series maturing on ${seriesMaturity * 1000}`);
  await periphery.sponsorSeries(adapterAddress, seriesMaturity, true).then(tx => tx.wait());
  console.log('SPONSORED!');
});
