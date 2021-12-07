const dayjs = require("dayjs");

module.exports = async function ({ ethers, getNamedAccounts }) {
  const divider = await ethers.getContract("Divider");
  const stake = await ethers.getContract("STAKE");
  const periphery = await ethers.getContract("Periphery");
  const { deployer } = await getNamedAccounts();

  const signer = await ethers.getSigner(deployer);

  console.log("Enable the Periphery to move the Deployer's STAKE for Series sponsorship");
  await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

  const balancerVault = await ethers.getContract("Vault");
  const spaceFactory = await ethers.getContract("SpaceFactory");

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

      console.log("Have the deployer issue the first 1,000,000 Target worth of Zeros/Claims for this Series");
      await divider.issue(adapter.address, seriesMaturity, ethers.utils.parseEther("1000000"));

      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const zero = new ethers.Contract(zeroAddress, tokenAbi, signer);
      const claim = new ethers.Contract(claimAddress, tokenAbi, signer);

      const zeroBalance = await zero.balanceOf(deployer);

      const { abi: spaceAbi } = await deployments.getArtifact("Space");
      const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
      const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
      const poolId = await pool.getPoolId();

      const { tokens } = await balancerVault.getPoolTokens(poolId);

      console.log("Sending Zeros to mock Balancer Vault");
      await zero.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const { defaultAbiCoder } = ethers.utils;

      console.log("Initializing Target in pool with the first Join");
      const { _zeroi, _targeti } = await pool.getIndices();
      const initialBalances = [null, null];
      initialBalances[_zeroi] = 0;
      initialBalances[_targeti] = ethers.utils.parseEther("1000000");

      const userData = defaultAbiCoder.encode(["uint[]"], [initialBalances]);
      await balancerVault
        .joinPool(poolId, deployer, deployer, {
          assets: tokens,
          maxAmountsIn: [ethers.constants.MaxUint256, ethers.constants.MaxUint256],
          fromInternalBalance: false,
          userData,
        })
        .then(tx => tx.wait());

      console.log("Making swap to init Zeros");
      await balancerVault
        .swap(
          {
            poolId,
            kind: 0, // given in
            assetIn: zero.address,
            assetOut: target.address,
            amount: ethers.utils.parseEther("500000"), // 500,000
            userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
          },
          { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
          0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
          ethers.constants.MaxUint256, // `deadline` – no deadline
        )
        .then(tx => tx.wait());

      // Sanity check that all the swaps on this testchain are working
      console.log(`--- Sanity check swaps ---`);

      await zero.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      console.log("swapping target for zeros");
      await periphery
        .swapTargetForZeros(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 0)
        .then(tx => tx.wait());

      console.log("swapping target for claims");
      await periphery
        .swapTargetForClaims(adapter.address, seriesMaturity, ethers.utils.parseEther("1"))
        .then(tx => tx.wait());

      console.log("swapping zeros for target");
      await zero.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await periphery
        .swapZerosForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"), 0)
        .then(tx => tx.wait());

      console.log("swapping claims for target");
      await claim.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await periphery
        .swapClaimsForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"))
        .then(tx => tx.wait());

      console.log("adding liquidity from target");
      await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await periphery
        .addLiquidityFromTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 1)
        .then(t => t.wait());
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
