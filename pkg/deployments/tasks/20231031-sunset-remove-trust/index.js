const { task } = require("hardhat/config");
const data = require("./input");

const contracts = require("../sunset-utils/contracts.json");
const { CHAINS } = require("../../hardhat.addresses");
const { fund, boostedGasPrice, stopPrank } = require("../../hardhat.utils");
const { startPrank } = require("../../hardhat.utils");
const { SENSE_ADMIN_ADDRESSES, printTxs, createBatchFile, getTx, getTrustedAddresses } = require("../sunset-utils/helpers");

task("20231031-sunset-remove-trust", "Removes Sense as trusted address").setAction(async (_, { ethers }) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const isFork = chainId == CHAINS.HARDHAT;
  console.log(`Deploying from ${deployer} on chain ${chainId}\n`);

  if (isFork) await startPrank(SENSE_ADMIN_ADDRESSES.multisig);

  // signers
  const multisigSigner = await ethers.getSigner(SENSE_ADMIN_ADDRESSES.multisig);
  const deployerSigner = await ethers.getSigner(deployer);

  // ABIs
  const { abi: dividerAbi } = await deployments.getArtifact("Divider");
  const { abi: trustAbi } = await deployments.getArtifact("Trust");

  // divider
  const { divider: dividerAddress } = data[chainId] || data[CHAINS.MAINNET];
  let divider = new ethers.Contract(dividerAddress, dividerAbi, multisigSigner);

  const SET_IS_TRUSTED_DATA = divider.interface.encodeFunctionData("setIsTrusted", [
    SENSE_ADMIN_ADDRESSES.multisig,
    false,
  ]);

  let multisigTxs = []; // store all multisig txs to create a JSON

  // Fund multisig
  if (isFork) await fund(deployerSigner, SENSE_ADMIN_ADDRESSES.multisig, ethers.utils.parseEther("1"));

  // (1). Turn permissionless mode ON
  if (!(await divider.permissionless())) {
    if (isFork) await divider.setPermissionless(true, { gasPrice: boostedGasPrice() }).then(t => t.wait());
    multisigTxs.push(
      getTx(
        dividerAddress,
        "setPermissionless",
        divider.interface.encodeFunctionData("setPermissionless", [true]),
      ),
    );
    console.log(`- Permissionless mode turned ON`);
  } else {
    console.log(`- Skipped as permissionless mode is already ON`);
  }

  // (2). For each contract, remove us as trusted addresses
  for (const address of Object.keys(contracts)) {
    for (const contract of contracts[address]) {
      console.log(`\n- Processing contract ${contract} -`);
      await removeTrust(contract);
    }
  }

  // Log functions to execute from multisig
  printTxs(multisigTxs);
  multisigTxs.forEach(tx => {
    delete tx.method;
  });

  // (3). Prepare JSON file with batched txs for Gnosis Safe Transaction Builder UI
  createBatchFile("sense-v1-sunset-batch-2", new Date().toISOString().slice(0, 10), multisigTxs);

  ////////// HELPERS //////////

  // make sure there are no more sense addresses trusted
  async function removeTrust(address) {
    let contract = new ethers.Contract(address, trustAbi, multisigSigner);

    // Validate if the contract has the 'isTrusted' method
    if (!(await isTrustContract(contract))) {
      console.log(`   * Is not a trust contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    if (trusted.sense.length === 0) {
      console.log(`   * No trusted addresses`);
      return;
    }

    const isDeployerTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.deployer);
    const isMultisigTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.multisig);
    contract = isDeployerTrusted ? contract.connect(deployerSigner) : contract;
    if (isFork && isDeployerTrusted) await stopPrank(SENSE_ADMIN_ADDRESSES.multisig);

    for (const trustAddress of trusted.sense) {
      if (isFork || isDeployerTrusted) {
        await contract.setIsTrusted(trustAddress, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());
      }

      if (!isDeployerTrusted && isMultisigTrusted) {
        multisigTxs.push(getTx(contract.address, "setIsTrusted", SET_IS_TRUSTED_DATA));
      }
    }

    console.log(`   * ${address} is no longer trusted`);
    if (trusted.other.length > 0) console.log(`   * Other trusted addresses: ${trusted.other}`);
    if (isFork && isDeployerTrusted) await startPrank(SENSE_ADMIN_ADDRESSES.multisig);
  }

  async function isTrustContract(contract) {
    try {
      await contract.isTrusted(SENSE_ADMIN_ADDRESSES.multisig);
      return true;
    } catch (e) {
      return false;
    }
  }
});
