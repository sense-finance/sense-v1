const fs = require("fs");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // IMPORTANT: this must be run *first*, so that it has the same address across deployments
  // (has the same deployment address and nonce)
  const pkgjson = JSON.parse(fs.readFileSync(`${__dirname}/../../package.json`, "utf-8"));
  await deploy("Versioning", {
    from: deployer,
    args: [pkgjson.version],
    log: true,
  });

  const versioning = await ethers.getContract("Versioning");
  console.log("\nDeploy Sense version", await versioning.version());

  console.log("\nDeploy a token handler for the Divider to use");
  const { address: tokenHandlerAddress } = await deploy("TokenHandler", {
    from: deployer,
    args: [],
    log: true,
  });

  // set the cup to the zero address (where unclaimed rewards will go if nobody settles)
  const cup = ethers.constants.AddressZero;

  console.log("\nDeploy the Divider");
  await deploy("Divider", {
    from: deployer,
    args: [cup, tokenHandlerAddress],
    log: true,
  });

  const divider = await ethers.getContract("Divider");
  const tokenHandler = await ethers.getContract("TokenHandler");

  console.log("Add the divider to the asset deployer");
  await (await tokenHandler.init(divider.address)).wait();

};

module.exports.tags = ["simulated:divider", "scenario:simulated"];
module.exports.dependencies = [];
