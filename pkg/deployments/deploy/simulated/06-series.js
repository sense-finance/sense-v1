const log = console.log;
const dayjs = require("dayjs");
const { ethers } = require("hardhat");
const {
  getDeployedAdapters,
  generatePermit,
  zeroAddress,
  one,
  oneMillion,
  fourtyThousand,
} = require("../../hardhat.utils");

const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
const ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;
const DEADLINE = dayjs().add(1, "day").unix();

module.exports = async function () {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);

  // contracts
  const divider = await ethers.getContract("Divider", signer);
  const stake = await ethers.getContract("STAKE", signer);
  const periphery = await ethers.getContract("Periphery", signer);
  const { abi: adapterAbi } = await deployments.getArtifact("BaseAdapter");

  const chainId = await getChainId();

  log("\n-------------------------------------------------------");
  log("\nDeploy the Permit2");
  await deploy("Permit2Clone", {
    from: deployer,
    args: [],
    log: true,
  });
  const permit2 = await ethers.getContract("Permit2Clone", signer);

  const adapters = await getDeployedAdapters();
  log("\n-------------------------------------------------------");
  log("SPONSOR SERIES & SANITY CHECK SWAPS");
  log("-------------------------------------------------------");
  log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
  if (!(await stake.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
    await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
  }

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
    if (!(await target.allowance(deployer, divider.address)).eq(ethers.constants.MaxUint256)) {
      await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());
    }

    let quote, signature, message;
    [signature, message] = await generatePermit(zeroAddress(), 0, zeroAddress(), permit2, chainId, signer);

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapters[targetName], adapterAbi, signer);
      const [, , stakeSize] = await adapter.getStakeAndTarget();

      log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      let { pt: ptAddress, yt: ytAddress } = await divider.series(adapter.address, seriesMaturity);
      if (ptAddress === ethers.constants.AddressZero) {
        const [signature, message] = await generatePermit(
          stake.address,
          stakeSize,
          periphery.address,
          permit2,
          chainId,
          signer,
        );
        quote = [stake.address, stake.address, stakeSize, zeroAddress(), zeroAddress(), "0x"];
        const { pt: _ptAddress, yt: _ytAddress } = await periphery.callStatic.sponsorSeries(
          adapter.address,
          seriesMaturity,
          true,
          { msg: message, sig: signature },
          quote,
        );
        ptAddress = _ptAddress;
        ytAddress = _ytAddress;
        await periphery
          .sponsorSeries(adapter.address, seriesMaturity, true, { msg: message, sig: signature }, quote)
          .then(tx => tx.wait());
      }

      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
      const yt = new ethers.Contract(ytAddress, tokenAbi, signer);
      const decimals = await target.decimals();

      log("Have the deployer issue the first 1,000,000 Target worth of PT/YT for this Series");
      if (!(await pt.balanceOf(deployer)).gte(fourtyThousand(decimals))) {
        await divider.issue(adapter.address, seriesMaturity, oneMillion(decimals)).then(tx => tx.wait());
      }

      const { abi: spaceAbi } = await deployments.getArtifact("lib/v1-space/src/Space.sol:Space");
      const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
      const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
      const poolId = await pool.getPoolId();

      log("Sending PT to mock Balancer Vault");
      if (!(await target.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      if (!(await pt.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        await pt.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      const { defaultAbiCoder } = ethers.utils;

      log("Make all Periphery approvals");
      if (!(await target.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await pool.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        await pool.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await pt.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await yt.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        await yt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      log("Initializing Target in pool with the first Join");

      let data = await balancerVault.getPoolTokens(poolId);
      let balances = data.balances;

      log("- adding liquidity via target");
      if (balances[0].lt(one(decimals))) {
        quote = [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"];
        await periphery
          .addLiquidity(
            adapter.address,
            seriesMaturity,
            one(decimals),
            [0, 0, 0],
            1,
            deployer,
            { msg: message, sig: signature },
            quote,
          )
          .then(t => t.wait());
      }

      // one side liquidity removal sanity check
      log("- removing liquidity when one side liquidity (skip swap as there would be no liquidity)");
      let lpBalance = await pool.balanceOf(deployer);
      if (lpBalance.gte(ethers.utils.parseEther("0"))) {
        quote = [zeroAddress(), target.address, 0, zeroAddress(), zeroAddress(), "0x"];
        await periphery
          .removeLiquidity(
            adapter.address,
            seriesMaturity,
            lpBalance,
            [0, [0, 0], 0],
            false,
            deployer,
            {
              msg: message,
              sig: signature,
            },
            quote,
          )
          .then(t => t.wait());
      }

      data = await balancerVault.getPoolTokens(poolId);
      balances = data.balances;

      log("- adding liquidity via target");
      if (balances[0].lt(oneMillion(decimals).mul(2))) {
        quote = [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"];
        await periphery
          .addLiquidity(
            adapter.address,
            seriesMaturity,
            oneMillion(decimals).mul(2),
            [0, 0, 0],
            1,
            deployer,
            { msg: message, sig: signature },
            quote,
          )
          .then(t => t.wait());
      }

      log("Making swap to init PT");
      quote = [zeroAddress(), target.address, 0, zeroAddress(), zeroAddress(), "0x"];
      data = await balancerVault.getPoolTokens(poolId);
      balances = data.balances;
      await periphery
        .swapPTs(
          adapter.address,
          seriesMaturity,
          fourtyThousand(decimals),
          DEADLINE,
          0,
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(t => t.wait());

      data = await balancerVault.getPoolTokens(poolId);
      balances = data.balances;

      const ptIn = one(decimals).div(10);
      const principalPriceInTarget = await balancerVault.callStatic
        .swap(
          {
            poolId,
            kind: 0, // given in
            assetIn: pt.address,
            assetOut: target.address,
            amount: ptIn,
            userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
          },
          { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
          0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
          ethers.constants.MaxUint256, // `deadline` – no deadline
        )
        .then(v => v.mul(ethers.BigNumber.from(10).pow(decimals)).div(ptIn));

      const _scale = await adapter.callStatic.scale();
      const scale = _scale.div(1e12).toNumber() / 1e6;
      const _principalInTarget =
        principalPriceInTarget.div(ethers.BigNumber.from(10).pow(decimals - 4)) /
        10 ** Math.abs(4 - decimals);
      const principalPriceInUnderlying = _principalInTarget * scale;

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

      quote = [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"];

      log("swapping target for pt");
      await periphery
        .swapForPTs(
          adapter.address,
          seriesMaturity,
          one(decimals),
          DEADLINE,
          0,
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(tx => tx.wait());

      log("swapping target for yt");
      await periphery
        .swapForYTs(
          adapter.address,
          seriesMaturity,
          one(decimals),
          DEADLINE,
          one(decimals),
          one(decimals),
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(tx => tx.wait());

      quote = [zeroAddress(), target.address, 0, zeroAddress(), zeroAddress(), "0x"];

      log("swapping pt for target");
      await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      await periphery
        .swapPTs(
          adapter.address,
          seriesMaturity,
          one(decimals).div(2),
          DEADLINE,
          0,
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(tx => tx.wait());

      log("swapping yt for target");
      await periphery
        .swapYTs(
          adapter.address,
          seriesMaturity,
          one(decimals).div(2),
          DEADLINE,
          0,
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(tx => tx.wait());

      log("adding liquidity via target");
      quote = [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"];
      await periphery
        .addLiquidity(
          adapter.address,
          seriesMaturity,
          one(decimals),
          [0, 0, 0],
          1,
          deployer,
          { msg: message, sig: signature },
          quote,
        )
        .then(t => t.wait());

      const peripheryDust = await target.balanceOf(periphery.address).then(t => t.toNumber());
      // If there's anything more than dust in the Periphery, throw
      if (peripheryDust > 100) {
        throw new Error("Periphery has an unexpected amount of Target dust");
      }
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = ["simulated:adapters"];
