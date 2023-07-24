const dayjs = require("dayjs");
const { CHAINS, BALANCER_VAULT, PERMIT2, DAI_TOKEN, ETH_TOKEN } = require("../../hardhat.addresses");
const {
  getDeployedAdapters,
  generateTokens,
  generatePermit,
  getQuote,
  one,
  fourtyThousand,
  oneMillion,
  tenMillion,
  zeroAddress,
  ONE_YEAR_SECONDS,
  oneHundred,
} = require("../../hardhat.utils");
const log = console.log;
const permit2Abi = require("./Permit2.json");
const DEADLINE = dayjs().add(1, "day").unix();

module.exports = async function () {
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const chainId = await getChainId();
  const oneEther = ethers.utils.parseEther("1").toString();

  // contracts
  const divider = await ethers.getContract("Divider", signer);
  const periphery = await ethers.getContract("Periphery", signer);
  const permit2 = new ethers.Contract(PERMIT2.get(chainId), permit2Abi, signer);
  const { abi: tokenAbi } = await deployments.getArtifact("Token");
  const { abi: adapterAbi } = await deployments.getArtifact("BaseAdapter");

  const adapters = await getDeployedAdapters();

  log("\n-------------------------------------------------------");
  log("SPONSOR SERIES");
  log("-------------------------------------------------------");

  for (let factory of global.mainnet.FACTORIES) {
    for (let t of factory(chainId).targets) {
      await sponsor(t);
    }
  }

  for (let adapter of global.mainnet.ADAPTERS) {
    await sponsor(adapter(chainId).target);
  }

  // PTs SWAPS
  async function _swapForPTs(adapter, maturity, quote) {
    const buyToken = await ethers.getContractAt(tokenAbi, quote.buyTokenAddress, signer);
    const sellToken = await ethers.getContractAt(tokenAbi, quote.sellTokenAddress, signer);
    const isETH = sellToken.address.toLowerCase() === ETH_TOKEN.get(chainId).toLowerCase();
    let decimals = 18;
    let signature, message;

    if (!isETH) {
      decimals = await sellToken.decimals();
      // load wallet with from sellToken
      await generateTokens(sellToken.address, deployer, signer);

      // approve permit2 to pull sellToken and generate message and signature
      await sellToken.approve(permit2.address, ethers.constants.MaxUint256);
    }

    [signature, message] = await generatePermit(
      sellToken.address,
      one(decimals),
      periphery.address,
      permit2,
      chainId,
      signer,
    );

    console.info(` - Swap ${isETH ? "ETH" : await sellToken.symbol()} for PTs...`);
    const { sellTokenAddress, buyTokenAddress, allowanceTarget, to, data } = quote;

    let receipt = await (
      await periphery.swapForPTs(
        adapter.address,
        maturity,
        one(decimals),
        DEADLINE,
        0, // min amount out
        deployer,
        { msg: message, sig: signature },
        [sellTokenAddress, buyTokenAddress, 0, allowanceTarget, to, data],
        {
          value: isETH ? one(decimals) : 0,
        },
      )
    ).wait();

    if (quote.buyTokenAddress !== zeroAddress()) {
      const boughtAmount = receipt.events.find(e => e.event === "BoughtTokens").args.boughtAmount;
      console.info(
        `  ${"✔"} Successfully sold ${ethers.utils.formatEther(one(decimals))} ${
          isETH ? "ETH" : await sellToken.symbol()
        } for ${ethers.utils.formatEther(boughtAmount)} ${await buyToken.symbol()} via 0x!`,
      );
    }
    console.info(
      `  ${"✔"} Successfully swapped ${
        quote.buyTokenAddress === zeroAddress()
          ? isETH
            ? "ETH"
            : await sellToken.symbol()
          : await buyToken.symbol()
      } for PTs!`,
    );
  }

  async function swapAllForPTs(adapter, maturity) {
    log("\n------------------------------");
    log("Swaps for PTs");
    log("------------------------------");
    let sellAddr, buyAddr, quote;

    log("\n1. Swap target for PTs");
    const targetAddr = await adapter.target();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the target's address
    quote = {
      sellTokenAddress: targetAddr,
      buyTokenAddress: zeroAddress(),
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapForPTs(adapter, maturity, quote, signer);

    log("\n2. Swap underlying for PTs");
    const underlyingAddr = await adapter.underlying();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the underlying's address
    quote = {
      sellTokenAddress: underlyingAddr,
      buyTokenAddress: zeroAddress(),
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapForPTs(adapter, maturity, quote, signer);

    log("\n3. Swap DAI for PTs");
    sellAddr = DAI_TOKEN.get(chainId);
    buyAddr = await adapter.underlying();
    quote = await getQuote(sellAddr, buyAddr, oneEther); // get quote from 0x-API
    await _swapForPTs(adapter, maturity, quote, signer);

    log("\n4. Swap ETH for PTs");
    sellAddr = ETH_TOKEN.get(chainId);
    buyAddr = await adapter.underlying();
    quote = await getQuote(sellAddr, buyAddr, oneEther);
    await _swapForPTs(adapter, maturity, quote, signer);
  }

  async function _swapPTs(adapter, maturity, ptAmt, quote, callStatic) {
    const buyToken = await ethers.getContractAt(tokenAbi, quote.buyTokenAddress, signer);
    const sellToken = await ethers.getContractAt(tokenAbi, quote.sellTokenAddress, signer);
    const pt = await ethers.getContractAt(tokenAbi, await divider.pt(adapter.address, maturity), signer);
    const decimals = await pt.decimals();
    const isETH = buyToken.address.toLowerCase() === ETH_TOKEN.get(chainId).toLowerCase();

    // approve permit2 to pull PTs and generate message and signature
    await pt.approve(permit2.address, ethers.constants.MaxUint256);
    const [signature, message] = await generatePermit(
      pt.address,
      ptAmt,
      periphery.address,
      permit2,
      chainId,
      signer,
    );

    if (!callStatic) console.info(` - Swap PTs for ${isETH ? "ETH" : await buyToken.symbol()}...`);
    const { sellTokenAddress, buyTokenAddress, allowanceTarget, to, data } = quote;
    const fnParams = [
      adapter.address,
      maturity,
      ptAmt,
      DEADLINE,
      0, // min amount out
      deployer,
      { msg: message, sig: signature },
      [sellTokenAddress, buyTokenAddress, 0, allowanceTarget, to, data],
    ];
    const amtOut = await periphery.callStatic.swapPTs(...fnParams);
    if (!callStatic) {
      const receipt = await (await periphery.swapPTs(...fnParams)).wait();
      console.info(
        `  ${"✔"} Successfully swapped PTs for ${
          quote.sellTokenAddress === zeroAddress()
            ? isETH
              ? "ETH"
              : await buyToken.symbol()
            : await sellToken.symbol()
        }!`,
      );
      if (quote.sellTokenAddress !== zeroAddress()) {
        const boughtAmount = receipt.events.find(e => e.event === "BoughtTokens").args.boughtAmount;
        console.info(
          `  ${"✔"} Successfully sold ${ethers.utils.formatEther(boughtAmount)} ${
            isETH ? "ETH" : await buyToken.symbol()
          } for ${ethers.utils.formatEther(one(decimals))} ${await sellToken.symbol()} via 0x!`,
        );
      }
    }
    return amtOut;
  }

  async function swapPTsForAll(adapter, maturity) {
    log("\n------------------------------");
    log("Swaps PTs");
    log("------------------------------");
    let quote, sellAddr, buyAddr;

    const pt = await ethers.getContractAt(tokenAbi, await divider.pt(adapter.address, maturity), signer);
    const ptAmt = one(await pt.decimals()).div(4);

    log("\n1. Swap PTs for target");
    const targetAddr = await adapter.target();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the target's address
    quote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: targetAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapPTs(adapter, maturity, ptAmt, quote);

    log("\n2. Swap PTs for underlying");
    const underlyingAddr = await adapter.underlying();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the underlying's address
    quote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: underlyingAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapPTs(adapter, maturity, ptAmt, quote, signer);

    log("\n3. Swap PTs for DAI");
    sellAddr = await adapter.underlying();
    buyAddr = DAI_TOKEN.get(chainId);
    // In order to know how much the PT we want to sell is worth in underlying we first do a staticCall and save the `underlyingAmt`
    // Then, we use this value to generate the quote so then the Periphery will do the underlying to DAI swap on 0x
    // TODO: check this, sometimes fails...
    const toUnderlyingQuote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: underlyingAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    let underlyingAmt = await _swapPTs(adapter, maturity, ptAmt, toUnderlyingQuote, true);
    quote = await getQuote(sellAddr, buyAddr, underlyingAmt.toString()); // get quote from 0x-API
    await _swapPTs(adapter, maturity, ptAmt, quote, signer);

    log("\n4. Swap PTs for ETH");
    sellAddr = await adapter.underlying();
    buyAddr = ETH_TOKEN.get(chainId);
    underlyingAmt = await _swapPTs(adapter, maturity, ptAmt, toUnderlyingQuote, true);
    quote = await getQuote(sellAddr, buyAddr, underlyingAmt.toString()); // get quote from 0x-API
    await _swapPTs(adapter, maturity, ptAmt, quote, signer);
  }

  // YTs SWAPS
  async function _swapForYTs(adapter, maturity, quote, signer) {
    const buyToken = await ethers.getContractAt(tokenAbi, quote.buyTokenAddress, signer);
    const sellToken = await ethers.getContractAt(tokenAbi, quote.sellTokenAddress, signer);
    const isETH = sellToken.address.toLowerCase() === ETH_TOKEN.get(chainId).toLowerCase();
    let decimals = 18;
    let signature, message;

    if (!isETH) {
      decimals = await sellToken.decimals();
      // load wallet with from sellToken
      await generateTokens(sellToken.address, deployer, signer);

      // approve permit2 to pull sellToken and generate message and signature
      await sellToken.approve(permit2.address, ethers.constants.MaxUint256);
    }
    [signature, message] = await generatePermit(
      sellToken.address,
      oneHundred(decimals),
      periphery.address,
      permit2,
      chainId,
      signer,
    );

    console.info(` - Swap ${isETH ? "ETH" : await sellToken.symbol()} for YTs...`);
    const { sellTokenAddress, buyTokenAddress, allowanceTarget, to, data } = quote;
    let receipt = await (
      await periphery.swapForYTs(
        adapter.address,
        maturity,
        one(decimals).mul(100), // we want to swap 1 DAI
        DEADLINE,
        quote.buyAmount || one(decimals), // this is the target to borrow (which is 1 DAI swapped to target). We should probably take into account the slippage
        0, // min amount out
        deployer,
        { msg: message, sig: signature },
        [sellTokenAddress, buyTokenAddress, 0, allowanceTarget, to, data],
        {
          value: isETH ? one(decimals) : 0,
        },
      )
    ).wait();

    if (quote.buyTokenAddress !== zeroAddress()) {
      const boughtAmount = receipt.events.find(e => e.event === "BoughtTokens").args.boughtAmount;
      console.info(
        `  ${"✔"} Successfully sold ${ethers.utils.formatEther(one(decimals))} ${
          isETH ? "ETH" : await sellToken.symbol()
        } for ${ethers.utils.formatEther(boughtAmount)} ${await buyToken.symbol()} via 0x!`,
      );
    }
    console.info(
      `  ${"✔"} Successfully swapped ${
        quote.buyTokenAddress === zeroAddress()
          ? isETH
            ? "ETH"
            : await sellToken.symbol()
          : await buyToken.symbol()
      } YTs!`,
    );
  }

  async function swapAllForYTs(adapter, maturity) {
    log("\n------------------------------");
    log("Swaps for YTs");
    log("------------------------------");
    let sellAddr, buyAddr, quote;

    log("\n1. Swap target for YTs");
    const targetAddr = await adapter.target();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the target's address
    quote = {
      sellTokenAddress: targetAddr,
      buyTokenAddress: zeroAddress(),
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapForYTs(adapter, maturity, quote, signer);

    log("\n2. Swap underlying for YTs");
    const underlyingAddr = await adapter.underlying();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the underlying's address
    quote = {
      sellTokenAddress: underlyingAddr,
      buyTokenAddress: zeroAddress(),
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapForYTs(adapter, maturity, quote, signer);

    log("\n3. Swap DAI for YTs");
    sellAddr = DAI_TOKEN.get(chainId);
    buyAddr = await adapter.underlying();
    quote = await getQuote(sellAddr, buyAddr, ethers.utils.parseEther("100").toString());
    await _swapForYTs(adapter, maturity, quote, signer);

    log("\n4. Swap ETH for YTs");
    sellAddr = ETH_TOKEN.get(chainId);
    buyAddr = await adapter.underlying();
    quote = await getQuote(sellAddr, buyAddr, oneEther);
    await _swapForYTs(adapter, maturity, quote, signer);
  }

  async function _swapYTs(adapter, maturity, ytAmt, quote, callStatic, signer, minAccepted) {
    const buyToken = await ethers.getContractAt(tokenAbi, quote.buyTokenAddress, signer);
    const sellToken = await ethers.getContractAt(tokenAbi, quote.sellTokenAddress, signer);
    const yt = await ethers.getContractAt(tokenAbi, await divider.yt(adapter.address, maturity), signer);
    const decimals = await yt.decimals();
    const isETH = buyToken.address.toLowerCase() === ETH_TOKEN.get(chainId).toLowerCase();

    // approve permit2 to pull YTs and generate message and signature
    await yt.approve(permit2.address, ethers.constants.MaxUint256);
    const [signature, message] = await generatePermit(
      yt.address,
      ytAmt,
      periphery.address,
      permit2,
      chainId,
      signer,
    );

    if (!callStatic) console.info(` - Swap YTs for ${isETH ? "ETH" : await buyToken.symbol()}...`);
    const { sellTokenAddress, buyTokenAddress, allowanceTarget, to, data } = quote;
    const fnParams = [
      adapter.address,
      maturity,
      ytAmt,
      DEADLINE,
      minAccepted || 0, // min accepted
      deployer,
      { msg: message, sig: signature },
      [sellTokenAddress, buyTokenAddress, 0, allowanceTarget, to, data],
    ];
    const amtOut = await periphery.callStatic.swapYTs(...fnParams);
    if (!callStatic) {
      const receipt = await (await periphery.swapYTs(...fnParams)).wait();
      console.info(
        `  ${"✔"} Successfully swapped YTs for ${
          quote.sellTokenAddress === zeroAddress()
            ? isETH
              ? "ETH"
              : await buyToken.symbol()
            : await sellToken.symbol()
        }!`,
      );
      if (quote.sellTokenAddress !== zeroAddress()) {
        const boughtAmount = receipt.events.find(e => e.event === "BoughtTokens").args.boughtAmount;
        console.info(
          `  ${"✔"} Successfully sold ${ethers.utils.formatEther(boughtAmount)} ${
            isETH ? "ETH" : await buyToken.symbol()
          } for ${ethers.utils.formatEther(one(decimals))} ${await sellToken.symbol()} via 0x!`,
        );
      }
    }
    return amtOut;
  }

  async function swapYTsForAll(adapter, maturity) {
    log("\n------------------------------");
    log("Swaps YTs");
    log("------------------------------");
    let sellAddr, buyAddr, quote;

    const yt = await ethers.getContractAt(tokenAbi, await divider.yt(adapter.address, maturity), signer);
    let ytAmt = one(await yt.decimals()).div(4);

    log("\n1. Swap YTs for target");
    const targetAddr = await adapter.target();
    // since we are swapping target, we only need the quote to have the sellTokenAddress with the target's address
    quote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: targetAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapYTs(adapter, maturity, ytAmt, quote, false, signer);

    log("\n2. Swap YTs for underlying");
    const underlyingAddr = await adapter.underlying();
    // since we are swapping underlying, we only need the quote to have the sellTokenAddress with the underlying's address
    quote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: underlyingAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    await _swapYTs(adapter, maturity, ytAmt, quote, false, signer);

    log("\n3. Swap YTs for DAI");
    ytAmt = fourtyThousand(await yt.decimals()).div(2);
    sellAddr = await adapter.underlying();
    buyAddr = DAI_TOKEN.get(chainId);
    // In order to know how much the YT we want to sell is worth in underlying we first do a staticCall and save it in `underlyingAmt`
    // Then, we use this value to generate the quote so then the Periphery will do the underlying to DAI swap on 0x
    const toUnderlyingQuote = {
      sellTokenAddress: zeroAddress(),
      buyTokenAddress: underlyingAddr,
      allowanceTarget: zeroAddress(),
      to: zeroAddress(),
      data: "0x",
    };
    let underlyingAmt = await _swapYTs(adapter, maturity, ytAmt, toUnderlyingQuote, true, signer);
    // As `underlyingAmt` is an estimation, it may happen that when we actually do the swap from YTs to Target on Space, we receive less
    // than this. If so, then the 0x swap will fail because it will be trying to pull more than what the Periphery is holding.
    // So, we have to decrease a little bit the amount of `underlyingAmt` expected.
    // In the following example, we decrease it by 1%.
    // NOTE that, after doing the whole swap of YTs for DAI, if there's a remainder of underlying (stETH)
    // they will be sent back to the user.
    // QUESTION: What's the ideal buffer? 1%? 0.5%? 0.1%?
    let scale = await adapter.callStatic.scale();
    let underlyingAmtMinusBuffer = underlyingAmt.mul(99).div(100);
    let targetAmtMinusBuffer = underlyingAmtMinusBuffer
      .mul(ethers.utils.parseEther("1"))
      .div(scale.toString());
    quote = await getQuote(sellAddr, buyAddr, underlyingAmtMinusBuffer.toString()); // get quote from 0x-API
    await _swapYTs(adapter, maturity, ytAmt, quote, false, signer, targetAmtMinusBuffer); // NOTE that minAccepted is in target

    log("\n4. Swap YTs for ETH");
    sellAddr = await adapter.underlying();
    buyAddr = ETH_TOKEN.get(chainId);
    underlyingAmt = await _swapYTs(adapter, maturity, ytAmt, toUnderlyingQuote, true, signer);
    scale = await adapter.callStatic.scale();
    underlyingAmtMinusBuffer = underlyingAmt.mul(99).div(100);
    targetAmtMinusBuffer = underlyingAmtMinusBuffer.mul(ethers.utils.parseEther("1")).div(scale.toString());
    quote = await getQuote(sellAddr, buyAddr, underlyingAmtMinusBuffer.toString()); // get quote from 0x-API
    await _swapYTs(adapter, maturity, ytAmt, quote, false, signer, targetAmtMinusBuffer);
  }

  async function sponsor(t) {
    const spaceFactory = await ethers.getContract("SpaceFactory", signer);
    const { abi: vaultAbi } = await deployments.getArtifact(
      "@sense-finance/v1-core/src/external/balancer/Vault.sol:BalancerVault",
    );
    const balancerVault = new ethers.Contract(BALANCER_VAULT.get(chainId), vaultAbi, signer);

    const { name: targetName, series, address: targetAddress } = t;
    const target = new ethers.Contract(targetAddress, tokenAbi, signer);

    log(`\nEnable the Periphery to move the deployer's ${targetName} for issuance`);
    if (!(await target.allowance(deployer, divider.address)).eq(ethers.constants.MaxUint256)) {
      await target.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
    }

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapters[targetName], adapterAbi, signer);

      const [, stakeAddress, stakeSize] = await adapter.getStakeAndTarget();
      const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);

      const balance = await stake.balanceOf(deployer); // deployer's stake balance
      if (balance.lt(stakeSize)) {
        // if fork from mainnet
        if (chainId == CHAINS.HARDHAT && process.env.FORK_TOP_UP == "true") {
          log(`Load deployer address with stake`);
          await generateTokens(stakeAddress, deployer, signer, stakeSize);
        } else {
          throw Error("Not enough stake funds on wallet");
        }
      }

      log(`Enable Permit2 @ ${permit2.address} to move the Deployer's stake`);
      await stake.approve(permit2.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      log(`Sponsor Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
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
        const quote = [stake.address, stake.address, stakeSize, zeroAddress(), zeroAddress(), "0x"];
        const { pt: _ptAddress, yt: _ytAddress } = await periphery.callStatic[
          "sponsorSeries(address,uint256,bool,(((address,uint256),uint256,uint256),bytes),(address,address,uint256,address,address,bytes))"
        ](adapter.address, seriesMaturity, true, { msg: message, sig: signature }, quote);
        ptAddress = _ptAddress;
        ytAddress = _ytAddress;
        await periphery[
          "sponsorSeries(address,uint256,bool,(((address,uint256),uint256,uint256),bytes),(address,address,uint256,address,address,bytes))"
        ](adapter.address, seriesMaturity, true, { msg: message, sig: signature }, quote).then(tx =>
          tx.wait(),
        );
        log(`${"✔"} Series successfully sponsored`);
      }
      log("\n-------------------------------------------------------\n");

      const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
      const yt = new ethers.Contract(ytAddress, tokenAbi, signer);
      const decimals = await target.decimals();

      log("Have the periphery issue the first 1,000,000 Target worth of PT/YT for this Series");
      if (!(await pt.balanceOf(deployer)).gte(fourtyThousand(decimals))) {
        const balance = await target.balanceOf(deployer); // deployer's stake balance
        if (balance.lt(oneMillion(decimals))) {
          // if fork from mainnet
          if (chainId == CHAINS.HARDHAT && process.env.FORK_TOP_UP == "true") {
            log(` - Load deployer 10 million target`);
            await generateTokens(target.address, deployer, signer, tenMillion(decimals));
          } else {
            throw Error("Not enough target funds on wallet");
          }
        }
        const [signature, message] = await generatePermit(
          target.address,
          oneMillion(decimals),
          periphery.address,
          permit2,
          chainId,
          signer,
        );
        await periphery
          .issue(
            adapter.address,
            seriesMaturity,
            oneMillion(decimals),
            deployer,
            { msg: message, sig: signature },
            [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"],
          )
          .then(tx => tx.wait());
      }

      const { abi: spaceAbi } = await deployments.getArtifact("lib/v1-space/src/Space.sol:Space");
      const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
      const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
      const poolId = await pool.getPoolId();

      log("\nSend PT to mock Balancer Vault");
      if (!(await target.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        await target.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      if (!(await pt.allowance(deployer, balancerVault.address)).eq(ethers.constants.MaxUint256)) {
        await pt.approve(balancerVault.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      const { defaultAbiCoder } = ethers.utils;

      log("\nMake all Permit2 approvals");
      if (!(await target.allowance(deployer, permit2.address)).eq(ethers.constants.MaxUint256)) {
        await target.approve(permit2.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await pool.allowance(deployer, permit2.address)).eq(ethers.constants.MaxUint256)) {
        await pool.approve(permit2.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await pt.allowance(deployer, permit2.address)).eq(ethers.constants.MaxUint256)) {
        await pt.approve(permit2.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }
      if (!(await yt.allowance(deployer, permit2.address)).eq(ethers.constants.MaxUint256)) {
        await yt.approve(permit2.address, ethers.constants.MaxUint256).then(tx => tx.wait());
      }

      log("\nInitialize Target in pool with the first join");

      let balances = (await balancerVault.getPoolTokens(poolId)).balances;

      log("- add liquidity via target");
      if (balances[0].lt(one(decimals))) {
        const [signature, message] = await generatePermit(
          target.address,
          one(decimals),
          periphery.address,
          permit2,
          chainId,
          signer,
        );
        await periphery
          .addLiquidity(
            adapter.address,
            seriesMaturity,
            one(decimals),
            [0, 0, 0],
            1,
            deployer,
            { msg: message, sig: signature },
            [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"],
          )
          .then(t => t.wait());
      }

      // one side liquidity removal sanity check
      log("- remove liquidity when one side liquidity (skip swap as there would be no liquidity)");
      let lpBalance = await pool.balanceOf(deployer);
      if (lpBalance.gte(ethers.utils.parseEther("0"))) {
        const [signature, message] = await generatePermit(
          pool.address,
          lpBalance,
          periphery.address,
          permit2,
          chainId,
          signer,
        );
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
            [zeroAddress(), target.address, 0, zeroAddress(), zeroAddress(), "0x"],
          )
          .then(t => t.wait());
      }

      balances = (await balancerVault.getPoolTokens(poolId)).balances;

      log("- add liquidity via target");
      if (balances[0].lt(oneMillion(decimals))) {
        const [signature, message] = await generatePermit(
          target.address,
          oneMillion(decimals),
          periphery.address,
          permit2,
          chainId,
          signer,
        );
        await periphery
          .addLiquidity(
            adapter.address,
            seriesMaturity,
            oneMillion(decimals),
            [0, 0, 0],
            1,
            deployer,
            { msg: message, sig: signature },
            [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"],
          )
          .then(t => t.wait());
      }

      let signature, message;
      log("- make swap to init PT");
      balances = (await balancerVault.getPoolTokens(poolId)).balances;
      [signature, message] = await generatePermit(
        pt.address,
        oneMillion(decimals),
        periphery.address,
        permit2,
        chainId,
        signer,
      );
      let quote = [zeroAddress(), target.address, 0, zeroAddress(), zeroAddress(), "0x"];
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

      balances = (await balancerVault.getPoolTokens(poolId)).balances;

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
      log(`--- Sanity check swaps ---\n`);
      await swapAllForPTs(adapter, seriesMaturity);
      await swapAllForYTs(adapter, seriesMaturity);
      await swapPTsForAll(adapter, seriesMaturity);
      await swapYTsForAll(adapter, seriesMaturity);

      log("\nAdd liquidity via target");
      [signature, message] = await generatePermit(
        target.address,
        one(decimals),
        periphery.address,
        permit2,
        chainId,
        signer,
      );
      await periphery
        .addLiquidity(
          adapter.address,
          seriesMaturity,
          one(decimals),
          [0, 0, 0],
          1,
          deployer,
          { msg: message, sig: signature },
          [target.address, zeroAddress(), 0, zeroAddress(), zeroAddress(), "0x"],
        )
        .then(t => t.wait());

      const peripheryDust = await target.balanceOf(periphery.address).then(t => t.toNumber());
      log(`Periphery Dust: ${peripheryDust}`);
      // If there's anything more than dust in the Periphery, throw
      if (peripheryDust > 8000) {
        throw new Error("Periphery has an unexpected amount of Target dust");
      }
    }
  }
};

module.exports.tags = ["prod:series", "scenario:prod"];
module.exports.dependencies = ["prod:factories"];
