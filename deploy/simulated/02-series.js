const dayjs = require("dayjs");

module.exports = async function ({ ethers, getNamedAccounts }) {
  const divider = await ethers.getContract("Divider");
  const stable = await ethers.getContract("STABLE");
  const periphery = await ethers.getContract("Periphery");
  const { deployer } = await getNamedAccounts();

  console.log("Enable the Periphery to move the Deployer's STABLE for Series sponsorship");
  await stable.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

  for (let targetName of global.TARGETS) {
    const target = await ethers.getContract(targetName);

    console.log("Enable the Divider to move the deployer's Target for issuance");
    await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of global.SERIES_MATURITIES) {
      const feed = await ethers.getContract(`${targetName}-AdminFeed`);

      console.log(`Initializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      await periphery.sponsorSeries(feed.address, seriesMaturity, 0).then(tx => tx.wait());

      console.log("Have the deployer issue the first Zeros/Claims for this Series");
      await divider.issue(feed.address, seriesMaturity, ethers.utils.parseEther("10"));
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:feeds"];
