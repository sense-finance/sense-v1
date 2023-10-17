const { task } = require("hardhat/config");

const contracts = require("../sunset-utils/contracts.json");
const { CHAINS } = require("../../hardhat.addresses");
const { fund, boostedGasPrice, zeroAddress, stopPrank } = require("../../hardhat.utils");
const { startPrank } = require("../../hardhat.utils");
const { printTxs, getTrustedAddresses, SENSE_ADMIN_ADDRESSES, createBatchFile, getTx } = require("../sunset-utils/helpers");

task("20231031-sunset-remove-rewards-recipients", "Removes Sense as rewards recipient").setAction(async (_, { ethers }) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const isFork = chainId == CHAINS.HARDHAT;
  console.log(`Deploying from ${deployer} on chain ${chainId}\n`);

  if (isFork) await startPrank(SENSE_ADMIN_ADDRESSES.multisig);

  // signers
  const multisigSigner = await ethers.getSigner(SENSE_ADMIN_ADDRESSES.multisig);
  const deployerSigner = await ethers.getSigner(deployer);

  // ABIs
  const { abi: extractableRewardAbi } = await deployments.getArtifact("ExtractableReward");

  let multisigTxs = []; // store all multisig txs to create a JSON

  // Fund multisig
  if (isFork) await fund(deployerSigner, SENSE_ADMIN_ADDRESSES.multisig, ethers.utils.parseEther("1"));

  // (1). For each contract, remove us as reward recipients
  for (const address of Object.keys(contracts)) {
    for (const contract of contracts[address]) {
      console.log(`\n- Processing contract ${contract} -`);
      await removeRewardsRecipient(contract);
    }
  }

  // Log functions to execute from multisig
  printTxs(multisigTxs);
  multisigTxs.forEach(tx => {
    delete tx.method;
  });

  // (2). Prepare JSON file with batched txs for Gnosis Safe Transaction Builder UI
  createBatchFile("sense-v1-sunset-batch-1", new Date().toISOString().slice(0, 10), multisigTxs);

  ////////// HELPERS //////////

  // set reward recipient to zero address
  async function removeRewardsRecipient(address) {
    let contract = new ethers.Contract(address, extractableRewardAbi, multisigSigner);

    // Check if contract is ExtractableReward.sol
    if (!(await isExtractableContract(contract))) {
      console.log(`   * Is not an extractable contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    const rewardsRecipient = (await contract.rewardsRecipient()).toLowerCase();
    const isDeployerTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.deployer);
    const isMultisigTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.multisig);

    if (Object.values(SENSE_ADMIN_ADDRESSES).includes(rewardsRecipient)) {
      contract = isDeployerTrusted ? contract.connect(deployerSigner) : contract;

      if (isFork && isDeployerTrusted) await stopPrank(SENSE_ADMIN_ADDRESSES.multisig);

      if (isFork || isDeployerTrusted) {
        await contract
          .setRewardsRecipient(zeroAddress(), { gasPrice: boostedGasPrice() })
          .then(t => t.wait());

        if (isFork) await startPrank(SENSE_ADMIN_ADDRESSES.multisig); // assuming this is how you restart the prank
      }

      if (!isDeployerTrusted && isMultisigTrusted) {
        multisigTxs.push(
          getTx(
            address,
            "setRewardsRecipient",
            contract.interface.encodeFunctionData("setRewardsRecipient", [zeroAddress()]),
          ),
        );
      }

      console.log(`   * Rewards recipient set to zero address`);
    } else {
      console.log(`   * Rewards recipient is already zero address`);
    }
  }

  async function isExtractableContract(contract) {
    try {
      await contract.rewardsRecipient();
      return true;
    } catch (e) {
      return false;
    }
  }
});
