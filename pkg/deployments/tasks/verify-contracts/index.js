const { task } = require("hardhat/config");
const data = require("./input");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task("verify-contracts", "Verifies contracts on Etherscan").setAction(async () => {
  const chainId = await getChainId();
  let { contracts } = data[chainId];
  console.log("\n-------------------------------------------------------");
  console.log("Verify contracts on chain", chainId);
  console.log("-------------------------------------------------------");
  for (const contract of contracts) {
    const { contractName, address, args } = contract;
    console.log(`\n`);
    await verifyOnEtherscan(contractName, address, args);
  }
});
