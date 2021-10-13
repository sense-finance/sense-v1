module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();

  console.log("Deploy a cFeed implementation");
  const { address: cFeedAddress } = await deploy("CFeed", {
    from: deployer,
    args: [],
    log: true,
  });

  const divider = await ethers.getContract("Divider");
  const DELTA = 150;
  // FIXME: set the airdrop token address to 0 while we work on this functionality
  const airdropToken = ethers.constants.AddressZero;

  console.log("Deploy cToken feed factory");
  await deploy("CFactory", {
    from: deployer,
    args: [cFeedAddress, divider.address, 150, airdropToken],
    log: true,
  });
  const cFactory = await ethers.getContract("CFactory");

  console.log("Trust cToken feed factory on the divider");
  await (await divider.setIsTrusted(cFactoryAddress, true)).wait();

  console.log("Trust dev on the cToken feed factory");
  await (await cFactory.setIsTrusted(dev, true)).wait();
};

module.exports.tags = ["Feeds"];
module.exports.dependencies = ["Divider"];
