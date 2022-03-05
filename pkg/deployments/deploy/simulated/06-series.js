const log = console.log;
const dayjs = require("dayjs");
const { ethers } = require("hardhat");
const { getDeployedAdapters } = require("../../hardhat.utils");

const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
const ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;

module.exports = async function () {
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);

  const divider = await ethers.getContract("Divider", signer);
  const stake = await ethers.getContract("STAKE", signer);
  const periphery = await ethers.getContract("Periphery", signer);

  const chainId = await getChainId();

  const ADAPTER_ABI = [
    "function stake() public view returns (address)",
    "function stakeSize() public view returns (uint256)",
    "function scale() public view returns (uint256)",
  ];
  const adapters = await getDeployedAdapters();
  log("\n-------------------------------------------------------");
  log("SPONSOR SERIES & SANITY CHECK SWAPS");
  log("-------------------------------------------------------");
  log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
  await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

  const balancerVault = await ethers.getContract("Vault", signer);
  const spaceFactory = await ethers.getContract("SpaceFactory", signer);

  for (let factory of global.dev.FACTORIES) {
    for (let t of factory(chainId).targets) {
      await sponsor(t);
    }
  }

  for (let adapter of global.dev.ADAPTERS) {
    await sponsor(adapter(chainId).target);
  }

  async function sponsor(t) {
    const { name: targetName, series } = t;
    const target = await ethers.getContract(targetName, signer);

    log("\n-------------------------------------------------------");
    log(`\nEnable the Divider to move the deployer's ${targetName} for issuance`);
    await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapters[targetName], ADAPTER_ABI, signer);
      log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      let { pt: ptAddress, yt: ytAddress } = await divider.series(adapter.address, seriesMaturity);
      console.log(ptAddress, ytAddress, "ytAddress");
      if (ptAddress === ethers.constants.AddressZero) {
        console.log("sponsoring series");
        const { pt: _ptAddress, yt: _ytAddress } = await periphery.callStatic.sponsorSeries(
          adapter.address,
          seriesMaturity,
          true,
        );
        ptAddress = _ptAddress;
        ytAddress = _ytAddress;
        await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());
      }

      log("Have the deployer issue the first 1,000,000 Target worth of PT/YT for this Series");
      await divider.issue(adapter.address, seriesMaturity, ethers.utils.parseEther("1000000")).then(tx => tx.wait());

      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
      const yt = new ethers.Contract(ytAddress, tokenAbi, signer);

      const { abi: spaceAbi } = await deployments.getArtifact("Space");
      const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
      const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
      const poolId = await pool.getPoolId();

      const { tokens } = await balancerVault.getPoolTokens(poolId);

      log("Sending PT to mock Balancer Vault");
      await pt.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const { defaultAbiCoder } = ethers.utils;

      log("Initializing Target in pool with the first Join");
      const { _pti, _targeti } = await pool.getIndices();
      const initialBalances = [null, null];
      initialBalances[_pti] = 0;
      initialBalances[_targeti] = ethers.utils.parseEther("2000000");

      const userData = defaultAbiCoder.encode(["uint[]"], [initialBalances]);
      await balancerVault
        .joinPool(poolId, deployer, deployer, {
          assets: tokens,
          maxAmountsIn: [ethers.constants.MaxUint256, ethers.constants.MaxUint256],
          fromInternalBalance: false,
          userData,
        })
        .then(tx => tx.wait());

      log("Making swap to init PT");
      await balancerVault
        .swap(
          {
            poolId,
            kind: 0, // given in
            assetIn: pt.address,
            assetOut: target.address,
            amount: ethers.utils.parseEther("40000"),
            userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
          },
          { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
          0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
          ethers.constants.MaxUint256, // `deadline` – no deadline
        )
        .then(tx => tx.wait());

      const principalPriceInTarget = await balancerVault.callStatic
        .swap(
          {
            poolId,
            kind: 0, // given in
            assetIn: pt.address,
            assetOut: target.address,
            amount: ethers.utils.parseEther("0.1"),
            userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
          },
          { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
          0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
          ethers.constants.MaxUint256, // `deadline` – no deadline
        )
        .then(v => v.div(1e10).toNumber() / 1e7);

      const scale = await adapter.callStatic.scale();
      const principalPriceInUnderlying = principalPriceInTarget * (scale.div(1e12).toNumber() / 1e6);

      const discountRate =
        ((1 / principalPriceInUnderlying) **
          (1 / ((dayjs(seriesMaturity * 1000).unix() - dayjs().unix()) / ONE_YEAR_SECONDS)) -
          1) *
        100;

      log(
        `
          Target ${targetName}
          Maturity: ${dayjs(seriesMaturity * 1000).format("YYYY-MM-DD")}
          Implied rate: ${discountRate}
          PT price in Target: ${principalPriceInTarget}
          PT price in Underlying: ${principalPriceInUnderlying}
        `,
      );

      // Sanity check that all the swaps on this testchain are working
      log(`--- Sanity check swaps ---`);

      await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await yt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await pool.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      log("swapping target for pt");
      await periphery
        .swapTargetForPTs(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 0)
        .then(tx => tx.wait());

      log("swapping target for yields");
      await periphery
        .swapTargetForYTs(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 0)
        .then(tx => tx.wait());

      log("swapping pt for target");
      await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await periphery
        .swapPTsForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"), 0)
        .then(tx => tx.wait());

      log("swapping yields for target");
      await periphery
        .swapYTsForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"))
        .then(tx => tx.wait());

      log("adding liquidity via target");
      await periphery
        .addLiquidityFromTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), 1)
        .then(t => t.wait());

      const peripheryDust = await target.balanceOf(periphery.address).then(t => t.toNumber());
      // If there's anything more than dust in the Periphery, throw
      if (peripheryDust > 100) {
        throw new Error("Periphery has an unexpected amount of Target dust");
      }

      log("removing liquidity to target");
      await periphery
        .removeLiquidityToTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("1"), [0, 0], 0)
        .then(t => t.wait());
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
