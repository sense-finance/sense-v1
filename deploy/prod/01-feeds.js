const COMP_TOKEN = new Map();
// DAI Mainnet
COMP_TOKEN.set("1", "0xc00e94cb662c3520282e6f5717214004a7f26888");
// DAI Local Mainnet fork
COMP_TOKEN.set("111", "0xc00e94cb662c3520282e6f5717214004a7f26888");
// TODO: Arbitrum

const DAI_TOKEN = new Map();
// DAI Mainnet
DAI_TOKEN.set("1", "0x6b175474e89094c44da98b954eedeac495271d0f");
// DAI Local Mainnet fork
DAI_TOKEN.set("111", "0x6b175474e89094c44da98b954eedeac495271d0f");
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
  });

  const divider = await ethers.getContract("Divider");
  const DELTA = 150;

  if (!DAI_TOKEN.has(chainId)) throw Error("No Dai token found");
  if (!COMP_TOKEN.has(chainId)) throw Error("No Comp token found");
  const compAddress = COMP_TOKEN.get(chainId);
  const daiAddress = DAI_TOKEN.get(chainId);

  const { address: baseWrapperAddress } = await deploy("BaseTWrapper", {
    from: deployer,
    args: [],
    log: true,
  });

  const ISSUANCE_FEE = ethers.utils.parseEther("0.01");
  const STAKE_SIZE = ethers.utils.parseEther("1");
  const MIN_MATURITY = "1209600"; // 2 weeks
  const MAX_MATURITY = "8467200"; // 14 weeks;
  console.log("Deploy cToken feed factory");
  await deploy("CFactory", {
    from: deployer,
    args: [
      cFeedAddress,
      baseWrapperAddress,
      divider.address,
      DELTA,
      compAddress,
      daiAddress,
      ISSUANCE_FEE,
      STAKE_SIZE,
      MIN_MATURITY,
      MAX_MATURITY,
    ],
    log: true,
  });

  const cFactory = await ethers.getContract("CFactory");

  console.log("Trust cToken feed factory on the divider");
  await (await divider.setIsTrusted(cFactory.address, true)).wait();

  console.log("Trust dev on the cToken feed factory");
  await (await cFactory.setIsTrusted(dev, true)).wait();
};

module.exports.tags = ["prod:feeds", "scenario:prod"];
module.exports.dependencies = ["prod:divider"];
