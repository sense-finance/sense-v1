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

  console.log("Deploy a cAdapter implementation");
  const { address: cAdapterAddress } = await deploy("CAdapter", {
    from: deployer,
    args: [],
    log: true,
  });

  const divider = await ethers.getContract("Divider");

  // FIXME: placeholder to be replaced with the real delta value once determined
  const DELTA = 150;

  if (!DAI_TOKEN.has(chainId)) throw Error("No Dai token found");
  if (!COMP_TOKEN.has(chainId)) throw Error("No Comp token found");
  const compAddress = COMP_TOKEN.get(chainId);
  const daiAddress = DAI_TOKEN.get(chainId);

  const ISSUANCE_FEE = ethers.utils.parseEther("0.01");
  const STAKE_SIZE = ethers.utils.parseEther("1");
  const MIN_MATURITY = "1209600"; // 2 weeks
  const MAX_MATURITY = "8467200"; // 14 weeks;
  console.log("Deploy cToken adapter factory");
  await deploy("CFactory", {
    from: deployer,
    args: [
      divider.address,
      cAdapterAddress,
      daiAddress,
      STAKE_SIZE,
      ISSUANCE_FEE,
      MIN_MATURITY,
      MAX_MATURITY,
      DELTA,
      compAddress,
    ],
    log: true,
  });

  const cFactory = await ethers.getContract("CFactory");

  console.log("Trust cToken adapter factory on the divider");
  await (await divider.setIsTrusted(cFactory.address, true)).wait();
};

module.exports.tags = ["prod:adapters", "scenario:prod"];
module.exports.dependencies = ["prod:divider"];
