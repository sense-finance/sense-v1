const log = console.log;
const dayjs = require("dayjs");
const { ethers } = require("hardhat");
const { getDeployedAdapters } = require("../../hardhat.utils");

const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
const ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;
const TWO_MILLION_ETH = ethers.utils.parseEther("2000000");
const ONE_ETH = ethers.utils.parseEther("1");
const FOURTY_THOUSAND_ETH = ethers.utils.parseEther("40000");  
const ONE_MILLION_ETH = ethers.utils.parseEther("1000000");  

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

    for (let seriesMaturity of series) {
      if (targetName === 'cDAI' && seriesMaturity == 1649030400) {
        const adapter = new ethers.Contract(adapters[targetName], ADAPTER_ABI, signer);
        // log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
        // let { pt: ptAddress, yt: ytAddress } = await divider.series(adapter.address, seriesMaturity);
        // if (ptAddress === ethers.constants.AddressZero) {
        //   const { pt: _ptAddress, yt: _ytAddress } = await periphery.callStatic.sponsorSeries(
        //     adapter.address,
        //     seriesMaturity,
        //     true,
        //   );
        //   ptAddress = _ptAddress;
        //   ytAddress = _ytAddress;
        //   await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());
        // }

        // const { abi: tokenAbi } = await deployments.getArtifact("Token");
        // const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
        // const yt = new ethers.Contract(ytAddress, tokenAbi, signer);

        // log("Have the deployer issue the first 1,000,000 Target worth of PT/YT for this Series");
        // if (!(await pt.balanceOf(deployer)).gte(FOURTY_THOUSAND_ETH)) {
        //   await divider.issue(adapter.address, seriesMaturity, ONE_MILLION_ETH).then(tx => tx.wait());
        // }

        const { abi: spaceAbi } = await deployments.getArtifact("Space");
        const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
        const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
        const poolId = await pool.getPoolId();

        // log("Sending PT to mock Balancer Vault");
        // if (!(await target.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        //   await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }

        // if (!(await pt.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        //   await pt.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }

        // const { defaultAbiCoder } = ethers.utils;

        // log("Make all Periphery approvals");
        // if (!(await target.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        //   await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }
        // if (!(await pool.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        //   await pool.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }
        // if (!(await pt.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        //   await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }
        // if (!(await yt.allowance(deployer, periphery.address)).eq(ethers.constants.MaxUint256)) {
        //   await yt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        // }

        // log("Initializing Target in pool with the first Join");

        let data = await balancerVault.getPoolTokens(poolId);
        let balances = data.balances;
        log("balances", balances);
        log("target balance", (await target.balanceOf(deployer)).toString());
        log("target allowance", (await target.allowance(deployer, periphery.address)).toString());


        // log("- adding liquidity via target");
        // if (balances[0].lt(ONE_ETH)) {
        //   await periphery
        //   .addLiquidityFromTarget(adapter.address, seriesMaturity, ONE_ETH, 1, 0)
        //   .then(t => t.wait());
        // }

        // // one side liquidity removal sanity check
        // log("- removing liquidity when one side liquidity (skip swap as there would be no liquidity)");
        // let lpBalance = await pool.balanceOf(deployer);
        // if (lpBalance.gte(ethers.utils.parseEther("0"))) {
        //   await periphery.removeLiquidity(adapter.address, seriesMaturity, lpBalance, [0, 0], 0, false, { gasLimit: 1000000, gasPrice: 6000000000 }).then(t => t.wait());
        // }

        log("- TESTTTTT");
        let lpBalance = await pool.balanceOf(deployer);
        log("lpBalance", lpBalance);
        await periphery.swapTargetForPTs(adapter.address, seriesMaturity, ONE_MILLION_ETH, 0).then(t => t.wait());

    //     data = await balancerVault.getPoolTokens(poolId);
    //     balances = data.balances;
    //     console.log("BALANCESSSS", data.balances[0].toString());
    //     console.log("BALANCESSSS", data.balances[1].toString());
        
    //     log("- adding liquidity via target");
    //     if (balances[0].lt(TWO_MILLION_ETH)) {
    //       await periphery
    //         .addLiquidityFromTarget(adapter.address, seriesMaturity, TWO_MILLION_ETH, 1, 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //         .then(t => t.wait());
    //     }
    //     data = await balancerVault.getPoolTokens(poolId);
    //     balances = data.balances;
    //     console.log("BALANCESSSS", data.balances[0].toString());
    //     console.log("BALANCESSSS", data.balances[1].toString());

    //     log("Making swap to init PT");
    //     data = await balancerVault.getPoolTokens(poolId);
    //     balances = data.balances;
    //     await periphery
    //       .swapPTsForTarget(adapter.address, seriesMaturity, FOURTY_THOUSAND_ETH, 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(t => t.wait());

    //     data = await balancerVault.getPoolTokens(poolId);
    //     balances = data.balances;
    //     console.log("BALANCESSSS", data.balances[0].toString());
    //     console.log("BALANCESSSS", data.balances[1].toString());

    //     const principalPriceInTarget = await balancerVault.callStatic
    //       .swap(
    //         {
    //           poolId,
    //           kind: 0, // given in
    //           assetIn: pt.address,
    //           assetOut: target.address,
    //           amount: ethers.utils.parseEther("0.1"),
    //           userData: defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
    //         },
    //         { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
    //         0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
    //         ethers.constants.MaxUint256, // `deadline` – no deadline
    //       )
    //       .then(v => v.div(1e10).toNumber() / 1e7);

    //     const scale = await adapter.callStatic.scale();
    //     const principalPriceInUnderlying = principalPriceInTarget * (scale.div(1e12).toNumber() / 1e6);

    //     const discountRate =
    //       ((1 / principalPriceInUnderlying) **
    //         (1 / ((dayjs(seriesMaturity * 1000).unix() - dayjs().unix()) / ONE_YEAR_SECONDS)) -
    //         1) *
    //       100;

    //     log(
    //       `
    //         Target ${targetName}
    //         Maturity: ${dayjs(seriesMaturity * 1000).format("YYYY-MM-DD")}
    //         Implied rate: ${discountRate}
    //         PT price in Target: ${principalPriceInTarget}
    //         PT price in Underlying: ${principalPriceInUnderlying}
    //       `,
    //     );

    //     // Sanity check that all the swaps on this testchain are working
    //     log(`--- Sanity check swaps ---`);

    //     log("swapping target for pt");
    //     await periphery
    //       .swapTargetForPTs(adapter.address, seriesMaturity, ONE_ETH, 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(tx => tx.wait());

    //     log("swapping target for yields");
    //     await periphery
    //       .swapTargetForYTs(adapter.address, seriesMaturity, ONE_ETH, 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(tx => tx.wait());

    //     log("swapping pt for target");
    //     await pt.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
    //     await periphery
    //       .swapPTsForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"), 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(tx => tx.wait());

    //     log("swapping yields for target");
    //     await periphery
    //       .swapYTsForTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.5"), { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(tx => tx.wait());

    //     log("adding liquidity via target");
    //     await periphery
    //       .addLiquidityFromTarget(adapter.address, seriesMaturity, ONE_ETH, 1, 0, { gasLimit: 1000000, gasPrice: 6000000000 })
    //       .then(t => t.wait());

    //     const peripheryDust = await target.balanceOf(periphery.address).then(t => t.toNumber());
    //     // If there's anything more than dust in the Periphery, throw
    //     if (peripheryDust > 100) {
    //       throw new Error("Periphery has an unexpected amount of Target dust");
    //     }
      }
    }
  }
};

module.exports.tags = ["simulated:series", "scenario:simulated"];
module.exports.dependencies = [];
