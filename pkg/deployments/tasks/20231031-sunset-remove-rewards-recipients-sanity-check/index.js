const { task } = require("hardhat/config");
const contracts = require("../sunset-utils/contracts.json");
const { zeroAddress } = require("../../hardhat.utils");

task("20231031-sunset-remove-rewards-recipients-sanity-check", "Checks Sense has been removed as rewards recipient").setAction(
  async (_, { ethers }) => {
    const { deployer } = await getNamedAccounts();

    // signers
    const deployerSigner = await ethers.getSigner(deployer);

    // ABIs
    const { abi: extractableRewardAbi } = await deployments.getArtifact("ExtractableReward");

    // Check if all contracts are sanitised (should be also called after running in multisig)
    await sanitiseExtractableContracts(contracts);

    ////////// HELPERS //////////

    async function isExtractableContract(contract) {
      try {
        await contract.rewardsRecipient();
        return true;
      } catch (e) {
        return false;
      }
    }

    // iterates over the contracts and check that we are not longer a rewards recipient
    async function sanitiseExtractableContracts(contracts) {
      for (const addresses of Object.values(contracts)) {
        for (const contractAddress of addresses) {
          const contract = new ethers.Contract(contractAddress, extractableRewardAbi, deployerSigner);
          if (
            (await isExtractableContract(contract)) &&
            (await contract.rewardsRecipient()).toLowerCase() !== zeroAddress()
          ) {
            throw new Error(`Extractable contract ${contractAddress} is not sanitised`);
          }
        }
      }
      console.log("All contracts are sanitised");
    }
  },
);
