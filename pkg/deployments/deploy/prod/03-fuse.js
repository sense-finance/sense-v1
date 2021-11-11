const FUSE_POOL_DIR = new Map();
// Mainnet
FUSE_POOL_DIR.set("1", "0x835482FE0532f169024d5E9410199369aAD5C77E");
// Local Mainnet fork
FUSE_POOL_DIR.set("111", "0x835482FE0532f169024d5E9410199369aAD5C77E");
// TODO: Arbitrum

const FUSE_COMPTROLLER_IMPL = new Map();
// Mainnet
FUSE_COMPTROLLER_IMPL.set("1", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");
// Local Mainnet fork
FUSE_COMPTROLLER_IMPL.set("111", "0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217");
// TODO: Arbitrum

const FUSE_CERC20_IMPL = new Map();
// Mainnet
FUSE_CERC20_IMPL.set("1", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");
// Local Mainnet fork
FUSE_CERC20_IMPL.set("111", "0x67db14e73c2dce786b5bbbfa4d010deab4bbfcf9");

const MASTER_ORACLE_IMPL = new Map();
// Mainnet
MASTER_ORACLE_IMPL.set("1", "0xb3c8ee7309be658c186f986388c2377da436d8fb");
// Local Mainnet fork
MASTER_ORACLE_IMPL.set("111", "0xb3c8ee7309be658c186f986388c2377da436d8fb");

module.exports = async function ({ ethers, deployments, getNamedAccounts, getChainId }) {
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;
  const chainId = await getChainId();

  const fusePoolDir = FUSE_POOL_DIR.get(chainId);
  const comptrollerImpl = FUSE_COMPTROLLER_IMPL.get(chainId);
  const fuseCERC20Impl = FUSE_CERC20_IMPL.get(chainId);
  const masterOracleImpl = MASTER_ORACLE_IMPL.get(chainId);

  const divider = await ethers.getContract("Divider");

  console.log("Deploying the Fuse pool manager");
  await deploy("PoolManager", {
    from: deployer,
    args: [fusePoolDir, comptrollerImpl, fuseCERC20Impl, divider.address, masterOracleImpl],
    log: true,
  });

  await deploy("MockOracle", {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ["prod:periphery", "scenario:prod"];
module.exports.dependencies = ["prod:feeds"];
