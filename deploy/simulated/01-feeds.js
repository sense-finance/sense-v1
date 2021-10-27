module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  for (let targetName of global.TARGETS) {
    console.log(`Deploying simulated ${targetName}`);
    await deploy(targetName, {
      contract: "Token",
      from: deployer,
      args: [targetName, targetName, 18, deployer],
      log: true,
    });

    const target = await ethers.getContract(targetName);
    const divider = await ethers.getContract("Divider");

    console.log(`Mint the deployer a balance of 1,000,000 ${targetName}`);
    await target.mint(deployer, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

    console.log(`Deploy TWrapper for ${targetName}`);
    await deploy(`${targetName}-BaseTWrapper`, {
      contract: "BaseTWrapper",
      from: deployer,
      args: [],
      log: true,
    });

    const twrapper = await ethers.getContract(`${targetName}-BaseTWrapper`);

    console.log(`Deploy a simulated reward token for ${targetName}`);
    const { address: rewardAddress } = await deploy(`${targetName}-Reward`, {
      contract: "Token",
      from: deployer,
      args: [`${targetName}-Reward`, `${targetName}-Reward`, 18, deployer],
      log: true,
    });
    await twrapper.initialize(target.address, divider.address, rewardAddress).then(tx => tx.wait());

    console.log(`Deploy admin feed for ${target.address} where ${deployer} can set the scale`);
    const { address: cDaiAdminFeedAddress } = await deploy(`${targetName}-AdminFeed`, {
      contract: "SimpleAdminFeed",
      from: deployer,
      args: [target.address, `${targetName} Feed`, targetName, twrapper.address],
      log: true,
    });

    console.log(`Adding ${target.address} admin feed to the Divider`);
    await divider.setFeed(cDaiAdminFeedAddress, true).then(tx => tx.wait());

    console.log(`Set ${targetName} issuance cap to max uint so we don't have to worry about it`);
    await divider.setGuard(target.address, ethers.constants.MaxUint256).then(tx => tx.wait());
  }
};

module.exports.tags = ["simulated:feeds", "scenario:simulated"];
module.exports.dependencies = ["simulated:divider"];
