const dayjs = require("dayjs");

module.exports = async function ({ ethers, getNamedAccounts }) {
  const divider = await ethers.getContract("Divider");
  const stake = await ethers.getContract("STAKE");
  const periphery = await ethers.getContract("Periphery");
  const factory = await ethers.getContract("MockFactory");
  const { deployer } = await getNamedAccounts();

  console.log("Enable the Periphery to move the Deployer's STAKE for Series sponsorship");
  await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

  for (let targetName of global.TARGETS) {
    const target = await ethers.getContract(targetName);

    console.log("Enable the Divider to move the deployer's Target for issuance");
    await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of global.SERIES_MATURITIES) {
      const adapterAddress = global.ADAPTERS[target.address];
      console.log('adapterAddress', adapterAddress);
      const mockAdapterImpl = await ethers.getContract('MockAdapter');
      const adapter = new ethers.Contract(adapterAddress, mockAdapterImpl.interface, ethers.provider);

      console.log(`Initializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      await periphery.sponsorSeries(adapter.address, seriesMaturity, 0).then(tx => tx.wait());

      console.log("Have the deployer issue the first Zeros/Claims for this Series");
      await divider.issue(adapter.address, seriesMaturity, ethers.utils.parseEther("10"));
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
