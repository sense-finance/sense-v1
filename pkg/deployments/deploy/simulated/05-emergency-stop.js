const { getDeployedAdapters } = require("../../hardhat.utils");
const { OZ_RELAYER } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const chainId = await getChainId();

  const divider = await ethers.getContract("Divider");

  log("\n-------------------------------------------------------")
  log("\nDeploy the EmergencyStop");
  const { address: emergencyAddress } = await deploy("EmergencyStop", {
    from: deployer,
    args: [divider.address],
    log: true,
  });

  log("Trust the emergency address on the divider");
  await (await divider.setIsTrusted(emergencyAddress, true)).wait();

  log("Can call stop");
  const adapters = await getDeployedAdapters();
  const emergency = await ethers.getContract("EmergencyStop");
  await emergency.callStatic.stop(Object.values(adapters));

  log("Trust the OZ Defender Relay address on the emergency stop contract");
  await (await emergency.setIsTrusted(OZ_RELAYER.get(chainId), true)).wait();
  
};

module.exports.tags = ["simulated:emergency-stop", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
