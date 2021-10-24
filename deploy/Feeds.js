const COMP_TOKEN = new Map();
// DAI Mainnet
COMP_TOKEN.set("1", "0xc00e94cb662c3520282e6f5717214004a7f26888");
// DAI Local Mainnet fork
COMP_TOKEN.set("111", "0xc00e94cb662c3520282e6f5717214004a7f26888");
// TODO: Arbitrum

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deploy } = deployments;
  const { deployer, dev } = await getNamedAccounts();
  const chainId = await getChainId();

  console.log("Deploy a cFeed implementation");
  const { address: cFeedAddress } = await deploy("CFeed", {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });

  const divider = await ethers.getContract("Divider");
  const DELTA = 150;

  if (!COMP_TOKEN.has(chainId)) throw Error("No stable token found");
  const compAddress = COMP_TOKEN.get(chainId);

  const { address: baseWrapperAddress } = await deploy("BaseTWrapper", {
    from: deployer,
    args: [],
    log: true,
  });

  console.log("Deploy cToken feed factory");
  await deploy("CFactory", {
    from: deployer,
    args: [cFeedAddress, baseWrapperAddress, divider.address, DELTA, compAddress],
    log: true,
    deterministicDeployment: true,
  });

  const cFactory = await ethers.getContract("CFactory");

  console.log("Trust cToken feed factory on the divider");
  await (await divider.setIsTrusted(cFactory.address, true)).wait();

  console.log("Trust dev on the cToken feed factory");
  await (await cFactory.setIsTrusted(dev, true)).wait();
};

module.exports.tags = ["Feeds"];
module.exports.dependencies = ["Divider"];
