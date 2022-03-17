const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

const { SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const balanceVaultAbi = require("./abi/Vault.json");
const spaceFactoryAbi = require("./abi/SpaceFactory.json");

const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
const ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;

const ADAPTER_ABI = [
  "function stake() public view returns (address)",
  "function stakeSize() public view returns (uint256)",
  "function scale() public returns (uint256)",
];

task(
  "20220316-initial-public-adapters",
  "Deploys, configures, and initialized liquidity for the first public Seires",
).setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  let spaceFactory = new ethers.Contract(mainnet.spaceFactory, spaceFactoryAbi, signer);
  let vault = new ethers.Contract(mainnet.vault, balanceVaultAbi, signer);
  let divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
  let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);
  let poolManager = new ethers.Contract(mainnet.poolManager, poolMangerAbi, signer);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Factories");
  for (let factory of mainnet.factories) {
    const {
      contractName: factoryContractName,
      ifee,
      stake,
      stakeSize,
      minm,
      maxm,
      mode,
      oracle,
      tilt,
      reward,
      targets,
    } = factory;
    console.log(
      `\nDeploy ${factoryContractName} with params ${JSON.stringify({
        ifee: ifee.toString(),
        stake,
        stakeSize: stakeSize.toString(),
        minm,
        maxm,
        mode,
        oracle,
        tilt,
        reward,
      })}}`,
    );
    const factoryParams = [oracle, ifee, stake, stakeSize, minm, maxm, mode, tilt];
    const { address: factoryAddress } = await deploy(factoryContractName, {
      from: deployer,
      args: [divider.address, factoryParams, reward],
      log: true,
    });

    console.log(`${factoryContractName} deployed to ${factoryAddress}`);

    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
      periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

      console.log(`\nAdd ${factoryContractName} support to Periphery`);
      await (await periphery.setFactory(factoryAddress, true)).wait();
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    }

    divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

    console.log("\n-------------------------------------------------------");
    console.log(`Deploy adapters for: ${factoryContractName}`);
    for (let t of targets) {
      const { name: targetName, series, address: targetAddress } = t;

      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const targetContract = new ethers.Contract(targetAddress, tokenAbi, signer);

      console.log(`\nOnboard target ${t.name} @ ${t.address} via Factory ${factoryContractName}`);
      const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, t.address);
      await (await periphery.deployAdapter(factoryAddress, t.address)).wait();
      console.log(`${t.name} adapterAddress: ${adapterAddress}`);

      if (chainId === "111") {
        console.log("\n-------------------------------------------------------");
        console.log("Checking multisig txs by impersonating the address");

        if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
        const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
        await hre.network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [senseAdminMultisigAddress],
        });
        const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

        divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
        console.log(`\nSet ${t.name} adapter issuance cap to ${t.guard}`);
        await divider.setGuard(adapterAddress, t.guard).then(tx => tx.wait());

        await hre.network.provider.request({
          method: "hardhat_stopImpersonatingAccount",
          params: [senseAdminMultisigAddress],
        });
      }

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);

      for (let seriesMaturity of series) {
        const adapter = new ethers.Contract(adapterAddress, ADAPTER_ABI, signer);

        console.log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
        const stakeAddress = await adapter.stake();
        const { abi: tokenAbi } = await deployments.getArtifact("Token");
        const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
        await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        const stakeSize = await adapter.stakeSize();
        const balance = await stake.balanceOf(deployer);
        if (balance.lt(stakeSize)) {
          throw Error("Not enough stake funds on wallet");
        }
        console.log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
        const { pt: ptAddress, yt: ytAddress } = await periphery.callStatic.sponsorSeries(
          adapter.address,
          seriesMaturity,
          true,
        );

        await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());

        console.log("\nEnable the Periphery to move the deployer's Target for liquidity provisions");
        await targetContract.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        console.log("\nEnable the Divider to move the deployer's Target for issuance");
        await targetContract.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        console.log("Series successfully sponsored");
        console.log("Target balance: ", await targetContract.balanceOf(deployer).then(t => t.toString()));
        const decimals = await targetContract.decimals().then(t => t.toString());

        console.log("Have the deployer issue PTs/YTs for this Series");
        await divider
          .issue(
            adapter.address,
            seriesMaturity,
            ethers.BigNumber.from("150").mul(ethers.BigNumber.from("10").pow(decimals)),
          )
          .then(tx => tx.wait());

        const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
        const ptBalance = await pt.balanceOf(deployer);
        console.log("PTs", ptBalance.toString());

        console.log("Adding liquidity via target");
        await periphery
          .addLiquidityFromTarget(
            adapter.address,
            seriesMaturity,
            ethers.BigNumber.from("1000").mul(ethers.BigNumber.from("10").pow(decimals)),
            1,
            0,
          )
          .then(t => t.wait());

        console.log("Approve Periphery to move PTs");
        await pt.approve(periphery.address, ethers.constants.MaxUint256).then(t => t.wait());

        await periphery
          .swapPTsForTarget(
            adapter.address,
            seriesMaturity,
            ptBalance.sub(ethers.BigNumber.from("1").mul(ethers.BigNumber.from("10").pow(parseInt(decimals) - 2))),
            0,
          )
          .then(t => t.wait());

        console.log("Calculating discount Rate");

        const { abi: spaceAbi } = await deployments.getArtifact("Space");
        const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
        const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
        const poolId = await pool.getPoolId();
        await pt.approve(vault.address, ethers.constants.MaxUint256).then(t => t.wait());
        await targetContract.approve(vault.address, ethers.constants.MaxUint256).then(tx => tx.wait());

        const principalPriceInTarget = await vault.callStatic
          .swap(
            {
              poolId,
              kind: 0, // given in
              assetIn: pt.address,
              assetOut: targetContract.address,
              amount: ethers.BigNumber.from("1").mul(ethers.BigNumber.from("10").pow(parseInt(decimals) - 4)),
              userData: ethers.utils.defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
            },
            { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
            0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
            ethers.constants.MaxUint256, // `deadline` – no deadline
          )
          .then(v => v.toNumber() / 1e4);

        const scale = await adapter.callStatic.scale();
        const principalPriceInUnderlying = principalPriceInTarget * (scale.div(1e12).toNumber() / 1e6);

        const discountRate =
          ((1 / principalPriceInUnderlying) **
            (1 / ((dayjs(seriesMaturity * 1000).unix() - dayjs().unix()) / ONE_YEAR_SECONDS)) -
            1) *
          100;

        console.log(
          `
          Target ${targetName}
          Scale ${scale}
          Maturity: ${dayjs(seriesMaturity * 1000).format("YYYY-MM-DD")}
          Implied rate: ${discountRate}
          PT price in Target: ${principalPriceInTarget}
          PT price in Underlying: ${principalPriceInUnderlying}
        `,
        );
      }
    }
  }

  for (let adapter of mainnet.adapters) {
    const { contractName, deploymentParams, target } = adapter;

    console.log(`\nDeploy ${contractName}`);
    const { address: adapterAddress } = await deploy(contractName, {
      from: deployer,
      args: [divider.address, ...Object.values(deploymentParams)],
      log: true,
    });
    console.log(`${contractName} adapter deployed at ${adapterAddress}`);

    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

      divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
      periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

      console.log(`Set ${contractName} adapter issuance cap to ${target.guard}`);
      await divider.setGuard(adapterAddress, target.guard).then(tx => tx.wait());

      console.log(`Verify ${contractName} adapter`);
      await periphery.verifyAdapter(adapterAddress, false).then(tx => tx.wait());

      console.log(`Onboard ${contractName} adapter`);
      await periphery.onboardAdapter(adapterAddress, true).then(tx => tx.wait());

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });
    }
    divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, signer);

    console.log(`Can call scale value`);
    const { abi: adapterAbi } = await deployments.getArtifact(contractName);
    const adptr = new ethers.Contract(adapterAddress, adapterAbi, signer);
    const scale = await adptr.callStatic.scale();
    console.log(`-> scale: ${scale.toString()}`);
    console.log(`${contractName} adapterAddress: ${adapterAddress}`);

    const { name: targetName, series, address: targetAddress } = target;
    const { abi: tokenAbi } = await deployments.getArtifact("Token");
    const targetContract = new ethers.Contract(targetAddress, tokenAbi, signer);

    console.log("\nEnable the Periphery to move the deployer's Target for liquidity provisions");
    await targetContract.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
    console.log("\nEnable the Divider to move the deployer's Target for issuance");
    await targetContract.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapterAddress, ADAPTER_ABI, signer);

      console.log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
      const stakeAddress = await adapter.stake();
      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
      await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const stakeSize = await adapter.stakeSize();
      const balance = await stake.balanceOf(deployer);
      if (balance.lt(stakeSize)) {
        throw Error("Not enough stake funds on wallet");
      }
      console.log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      const { pt: ptAddress, yt: ytAddress } = await periphery.callStatic.sponsorSeries(
        adapter.address,
        seriesMaturity,
        true,
      );

      await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());

      console.log("Series successfully sponsored");
      console.log("Target balance: ", await targetContract.balanceOf(deployer).then(t => t.toString()));

      console.log("Have the deployer issue PTs/YTs for this Series");
      await divider.issue(adapter.address, seriesMaturity, ethers.utils.parseEther("0.023")).then(tx => tx.wait());

      const pt = new ethers.Contract(ptAddress, tokenAbi, signer);
      const ptBalance = await pt.balanceOf(deployer);
      console.log("PTs", ptBalance.toString());

      console.log("Adding liquidity via target");
      await periphery
        .addLiquidityFromTarget(adapter.address, seriesMaturity, ethers.utils.parseEther("0.1"), 1, 0)
        .then(t => t.wait());

      console.log("Approve Periphery to move PTs");
      await pt.approve(periphery.address, ethers.constants.MaxUint256).then(t => t.wait());

      await periphery
        .swapPTsForTarget(
          adapter.address,
          seriesMaturity,
          ptBalance.sub(ethers.utils.parseEther("0.001").toString()),
          0,
        )
        .then(t => t.wait());

      console.log("Calculating discount Rate");

      const { abi: spaceAbi } = await deployments.getArtifact("Space");
      const poolAddress = await spaceFactory.pools(adapter.address, seriesMaturity);
      const pool = new ethers.Contract(poolAddress, spaceAbi, signer);
      const poolId = await pool.getPoolId();
      await pt.approve(vault.address, ethers.constants.MaxUint256).then(t => t.wait());
      await targetContract.approve(vault.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const principalPriceInTarget = await vault.callStatic
        .swap(
          {
            poolId,
            kind: 0, // given in
            assetIn: pt.address,
            assetOut: targetContract.address,
            amount: ethers.utils.parseEther("0.0001"),
            userData: ethers.utils.defaultAbiCoder.encode(["uint[]"], [[0, 0]]),
          },
          { sender: deployer, fromInternalBalance: false, recipient: deployer, toInternalBalance: false },
          0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
          ethers.constants.MaxUint256, // `deadline` – no deadline
        )
        .then(v => v.div(1e10).toNumber() / 1e4);

      const scale = await adapter.callStatic.scale();
      const principalPriceInUnderlying = principalPriceInTarget * (scale.div(1e12).toNumber() / 1e6);

      const discountRate =
        ((1 / principalPriceInUnderlying) **
          (1 / ((dayjs(seriesMaturity * 1000).unix() - dayjs().unix()) / ONE_YEAR_SECONDS)) -
          1) *
        100;

      console.log(
        `
        Target ${targetName}
        Scale ${scale}
        Maturity: ${dayjs(seriesMaturity * 1000).format("YYYY-MM-DD")}
        Implied rate: ${discountRate}
        PT price in Target: ${principalPriceInTarget}
        PT price in Underlying: ${principalPriceInUnderlying}
      `,
      );
    }
  }
});
