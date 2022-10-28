const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS, VERIFY_CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const poolManagerAbi = require("./abi/PoolManager.json");
const peripheryAbi = require("./abi/Periphery.json");

const { verifyOnEtherscan } = require("../../hardhat.utils");

task("20221029-LATER-periphery", "Deploys and authenticates a new Periphery").setAction(async (_, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
  const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);

  const {
    divider: dividerAddress,
    periphery: oldPeripheryAddress,
    poolManager: poolManagerAddress,
    spaceFactory: spaceFactoryAddress,
    balancerVault: balancerVaultAddress,
  } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
  let oldPeriphery = new ethers.Contract(oldPeripheryAddress, peripheryAbi, deployerSigner);
  let poolManager = new ethers.Contract(poolManagerAddress, poolManagerAbi, deployerSigner);

  console.log("\n-------------------------------------------------------");
  console.log("\nDeploy Periphery");
  const { address: peripheryAddress } = await deploy("Periphery", {
    from: deployer,
    args: [divider.address, poolManagerAddress, spaceFactoryAddress, balancerVaultAddress],
    log: true,
  });
  console.log(`Periphery deployed to ${peripheryAddress}`);

  console.log("\nVerifying pre-approved adapters on Periphery");
  const adaptersOnboarded = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterOnboarded(null))).map(e => e.args.adapter),
    ),
  ];
  console.log("Adapters to onborad:", adaptersOnboarded);

  const adaptersVerified = [
    ...new Set(
      (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterVerified(null))).map(e => e.args.adapter),
    ),
  ];
  console.log("Adapters to verify:", adaptersVerified);

  const newPeriphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);

  for (let adapter of adaptersOnboarded) {
    console.log("Onboarding adapter", adapter);
    await newPeriphery.onboardAdapter(adapter, false).then(t => t.wait());
  }

  for (let adapter of adaptersOnboarded) {
    console.log("Verifying adapter", adapter);
    await newPeriphery.verifyAdapter(adapter, false).then(t => t.wait());
  }

  console.log("\nAdding admin multisig as admin on Periphery");
  await newPeriphery.setIsTrusted(senseAdminMultisigAddress, true).then(t => t.wait());

  console.log("\nRemoving deployer as admin on Periphery");
  await newPeriphery.setIsTrusted(deployer, false).then(t => t.wait());

  // If we're in a forked environment, check the txs we need to send from the multisig as well
  if (chainId !== CHAINS.HARDHAT) {
    console.log("\n-------------------------------------------------------");
    await verifyOnEtherscan(peripheryAddress, [
      divider.address,
      poolManager.address,
      spaceFactoryAddress,
      balancerVaultAddress,
    ]);
  } else {
    // fund multisig
    console.log(`\nFund multisig to be able to make calls from that address`);
    await (
      await deployerSigner.sendTransaction({
        to: senseAdminMultisigAddress,
        value: ethers.utils.parseEther("1"),
      })
    ).wait();

    // impersonate multisig
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [senseAdminMultisigAddress],
    });

    const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
    oldPeriphery = oldPeriphery.connect(multisigSigner);
    divider = divider.connect(multisigSigner);
    poolManager = poolManager.connect(multisigSigner);

    console.log("\nUnset the multisig as an authority on the old Periphery");
    await (await oldPeriphery.setIsTrusted(senseAdminMultisigAddress, false)).wait();

    console.log("\nSet the periphery on the Divider");
    await (await divider.setPeriphery(peripheryAddress)).wait();

    console.log("\nRemove the old Periphery auth over the pool manager");
    await (await poolManager.setIsTrusted(oldPeriphery.address, false)).wait();

    console.log("\nGive the new Periphery auth over the pool manager");
    await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();

    // TOOD: we don't need this right? It was on the '20220313-periphery' but don't remember why?
    const ptOracleAddress = await poolManager.ptOracle();
    const lpOracleAddress = await poolManager.lpOracle();

    const ptOracle = new ethers.Contract(
      ptOracleAddress,
      [
        "function setTwapPeriod(uint256 _twapPeriod) external",
        "function twapPeriod() external view returns (uint256)",
      ],
      multisigSigner,
    );

    const lpOracle = new ethers.Contract(
      lpOracleAddress,
      [
        "function setTwapPeriod(uint256 _twapPeriod) external",
        "function twapPeriod() external view returns (uint256)",
      ],
      multisigSigner,
    );

    const iface = new ethers.utils.Interface(["function setTwapPeriod(uint256 _twapPeriod) external"]);
    const setTwapData = iface.encodeFunctionData("setTwapPeriod", [
      19800, // 5.5 hours in seconds
    ]);

    console.log("\nPrevious PT oracle twap period:", (await ptOracle.twapPeriod()).toString());
    await poolManager.execute(ptOracle.address, 0, setTwapData, 5000000).then(t => t.wait());
    console.log("New PT oracle twap period:", (await ptOracle.twapPeriod()).toString());

    console.log("\nPrevious LP oracle twap period:", (await lpOracle.twapPeriod()).toString());
    await poolManager.execute(lpOracle.address, 0, setTwapData, 5000000).then(t => t.wait());
    console.log("New LP oracle twap period:", (await lpOracle.twapPeriod()).toString());
  }

  if (VERIFY_CHAINS.includes(chainId)) {
    console.log("\n-------------------------------------------------------");
    console.log("\nACTIONS TO BE DONE ON DEFENDER: ");
    console.log("\n1. Unset the multisig as an authority on the old Periphery");
    console.log("\n2. Set the periphery on the Divider");
    console.log("\n3. Remove the old Periphery auth over the pool manager");
    console.log("\n4. Give the new Periphery auth over the pool manager");
    console.log("\n5. Set twap period for PT oracle"); // TODO: do we need this?
    console.log("\n6. Set twap period for LP oracle"); // TODO: do we need this?
  }
  console.log("\n-------------------------------------------------------");
});
