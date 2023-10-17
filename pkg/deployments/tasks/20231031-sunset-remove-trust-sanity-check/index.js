const { task } = require("hardhat/config");

const contracts = require("../sunset-utils/contracts.json");
const { SENSE_ADMIN_ADDRESSES } = require("../sunset-utils/helpers");

task("20231031-sunset-remove-trust-sanity-check", "Checks trust has been removed").setAction(async (_, { ethers }) => {
  const { deployer } = await getNamedAccounts();
  const deployerSigner = await ethers.getSigner(deployer);
  const { abi: trustAbi } = await deployments.getArtifact("Trust");

  // Check if all contracts are sanitised (should be also called after running in multisig)
  await sanitiseTrustContracts(contracts);

  async function isTrustContract(contract) {
    try {
      await contract.isTrusted(SENSE_ADMIN_ADDRESSES.multisig);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // iterates over the contracts and check that we are not longer trusted
  async function sanitiseTrustContracts(allContracts) {
    for (const addresses of Object.values(allContracts)) {
      for (const contractAddress of addresses) {
        const contract = new ethers.Contract(contractAddress, trustAbi, deployerSigner);
        for (const address of Object.values(SENSE_ADMIN_ADDRESSES)) {
          if ((await isTrustContract(contract)) && (await contract.isTrusted(address))) {
            throw new Error(`Trust contract ${contractAddress} is not sanitised. It's still trusting ${address}`);
          }
        }
      }
    }
    console.log("All contracts are sanitised");
  }
});
