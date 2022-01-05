const dayjs = require("dayjs");

module.exports = async function ({ ethers, getNamedAccounts }) {
  const divider = await ethers.getContract("Divider");
  const stake = await ethers.getContract("STAKE");
  const periphery = await ethers.getContract("Periphery");
  const { deployer } = await getNamedAccounts();

  const signer = await ethers.getSigner(deployer);

  console.log("Enable the Periphery to move the Deployer's STAKE for Series sponsorship");
  await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

  const mockBalancerVault = await ethers.getContract("MockBalancerVault");

  for (let targetName of global.TARGETS) {
    const target = await ethers.getContract(targetName);

    console.log("Enable the Divider to move the deployer's Target for issuance");
    await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of global.SERIES_MATURITIES) {
      const adapterAddress = global.ADAPTERS[targetName];
      const mockAdapterImpl = await ethers.getContract("MockAdapter");
      const adapter = new ethers.Contract(adapterAddress, mockAdapterImpl.interface, signer);

      const { zero: zeroAddress, claim: claimAddress } = await periphery.callStatic.sponsorSeries(
        adapter.address,
        seriesMaturity,
      );
      console.log(`Initializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      await periphery.sponsorSeries(adapter.address, seriesMaturity).then(tx => tx.wait());

      console.log("Have the deployer issue the first 10,000 Target worth of Zeros/Claims for this Series");
      await divider.issue(adapter.address, seriesMaturity, ethers.utils.parseEther("10000"));

      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const zero = new ethers.Contract(zeroAddress, tokenAbi, signer);
      const claim = new ethers.Contract(claimAddress, tokenAbi, signer);

      const zeroBalance = await zero.balanceOf(deployer);

      console.log("Sending Zeros to mock Balancer Vault");
      await zero.transfer(mockBalancerVault.address, zeroBalance).then(tx => tx.wait());

      const underlying = new ethers.Contract(await adapter.underlying(), tokenAbi, signer);

      console.log("Minting Underyling for the Balancer Vault");
      await underlying.mint(mockBalancerVault.address, zeroBalance).then(tx => tx.wait());

      console.log(`--- Sanity check swap ---`);
      await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      await periphery
        .swapTargetForZeros(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 0)
        .then(tx => tx.wait());
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
