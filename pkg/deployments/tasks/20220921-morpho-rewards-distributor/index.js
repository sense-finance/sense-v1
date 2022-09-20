const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const { SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const { verifyOnEtherscan } = require("../../hardhat.utils");

task(
  "20220921-morpho-rewards-distributor",
  "Deploys a MORPHO rewards distributor with the Sense multisig as the owner",
).setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  const { MORPHO } = mainnet;

  const { address: rewardsDistributorAddress } = await deploy("RewardsDistributor", {
    from: deployer,
    args: [MORPHO],
    log: true,
  });

  console.log(
    `Deployed MORPHO rewards distributor to address ${rewardsDistributorAddress} assuming the MORPHO token address is ${MORPHO}`,
  );

  let rewardsDistributor = await ethers.getContract("RewardsDistributor", deployerSigner);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("Sense multisig not found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  await rewardsDistributor.transferOwnership(senseAdminMultisigAddress);

  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(rewardsDistributorAddress, [MORPHO]);
  } else {
    // SANITY CHECKS
    console.log("\n-------------------------------------------------------");
    console.log("Hardhat sanity checks");

    const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);

    console.log("Check deployer auth");
    try {
      await rewardsDistributor.updateRoot(ethers.utils.formatBytes32String(""));
      throw new Error("Deployer shouldn't be able to update the root");
    } catch (err) {}

    await (
      await deployerSigner.sendTransaction({
        to: senseAdminMultisigAddress,
        value: ethers.utils.parseEther("1"),
      })
    ).wait();

    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [senseAdminMultisigAddress],
    });

    rewardsDistributor = rewardsDistributor.connect(multisigSigner);

    console.log("Check Sense multisig auth");
    if ((await rewardsDistributor.owner()) != senseAdminMultisigAddress)
      throw new Error("Onwer should be the Sense Multisig");

    try {
      await rewardsDistributor.updateRoot(ethers.utils.formatBytes32String(""));
    } catch (err) {
      console.log(err);
      throw new Error("Sense multisig should be able to update the root");
    }
  }
});
