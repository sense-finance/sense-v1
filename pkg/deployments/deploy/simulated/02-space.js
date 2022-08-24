const log = console.log;
const { WETH_TOKEN } = require("../../hardhat.addresses");

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();
  const divider = await ethers.getContract("Divider", signer);

  log("\n-------------------------------------------------------");
  log("\nDeploy Space & Space dependencies");
  const { address: authorizerAddress } = await deploy("Authorizer", {
    from: deployer,
    args: [deployer],
    log: true,
  });
  const { address: balancerVaultAddress } = await deploy("Vault", {
    from: deployer,
    args: [authorizerAddress, WETH_TOKEN.get(chainId), 0, 0],
    log: true,
  });

  const queryProcessor = await deploy("QueryProcessor", {
    from: deployer,
  });

  // For Space.
  const TS = ethers.utils
    .parseEther("1")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("31622400"));
  const G1 = ethers.utils
    .parseEther("950")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("1000"));
  const G2 = ethers.utils
    .parseEther("1000")
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("950"));
  const oracleEnabled = true;

  await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVaultAddress, divider.address, TS, G1, G2, oracleEnabled],
    libraries: {
      QueryProcessor: queryProcessor.address,
    },
    log: true,
  });
};

module.exports.tags = ["simulated:space", "scenario:simulated"];
module.exports.dependencies = ["simulated:fuse"];
