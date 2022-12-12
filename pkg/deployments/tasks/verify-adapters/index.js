const { task } = require("hardhat/config");
const data = require("./input");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task("verify-adapters", "Verifies adapters on Etherscan").setAction(async () => {
  const chainId = await getChainId();
  let { adapters } = data[chainId];
  console.log("\n-------------------------------------------------------");
  console.log("Verify adapters");
  console.log("-------------------------------------------------------");
  for (const adapter of adapters) {
    const { contractName, address, divider, target, rewardsRecipient, ifee, adapterParams } = adapter;
    console.log(`\n`);
    await verifyOnEtherscan(contractName, address, [divider, target, rewardsRecipient, ifee, adapterParams]);
  }
});
