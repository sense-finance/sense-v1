const { BALANCER_VAULT } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();

  if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
  const balancerVault = BALANCER_VAULT.get(chainId);

  const divider = await ethers.getContract("Divider");

  log("\n-------------------------------------------------------");
  log("\nDeploy Space Factory");

  const queryProcessor = await deploy("QueryProcessor", {
    from: deployer,
  });

  // For Space.
  const TS = ethers.utils.parseEther("1").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("31622400")); // TOODO(launch)
  const G1 = ethers.utils.parseEther("950").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("1000")); // TOODO(launch)
  const G2 = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("950")); // TOODO(launch)
  const oracleEnabled = true;

  await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVault, divider.address, TS, G1, G2, oracleEnabled],
    libraries: {
      QueryProcessor: queryProcessor.address,
    },
    log: true,
  });
};

module.exports.tags = ["prod:space", "scenario:prod"];
module.exports.dependencies = ["prod:fuse"];
