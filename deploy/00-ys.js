module.exports = async function ({
  ethers,
  deployments,
  getNamedAccounts,
  getChainId,
}) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const ts = ethers.utils.parseEther("1").div(ethers.BigNumber.from(315576000));

  const g1 = ethers.utils
    .parseEther("1")
    .mul(100)
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("1").mul(95));

  const g2 = ethers.utils
    .parseEther("1")
    .mul(95)
    .mul(ethers.utils.parseEther("1"))
    .div(ethers.utils.parseEther("1").mul(100));

  const { address: feedAddress } = await deploy("Feed", {
    from: deployer,
    args: [],
    log: true,
  });
  const { address: dividerAddress } = await deploy("Divider", {
    from: deployer,
    args: [],
    log: true,
  });

  const maturity = 100;

  await deploy("YS", {
    from: deployer,
    args: [
      global.MAINNET_VAULT,
      feedAddress,
      maturity,
      dividerAddress,
      ts,
      g1,
      g2,
    ],
    log: true,
  });
};

module.exports.tags = ["ys"];
module.exports.dependencies = [];
