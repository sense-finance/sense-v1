const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { BALANCER_VAULT, SENSE_MULTISIG } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const spaceFactoryAbi = require("./abi/SpaceFactory.json");
const poolManagerAbi = require("./abi/PoolManager.json");
const oldPeripheryAbi = require("./abi/OldPeriphery.json");
const newPeripheryAbi = require("./abi/NewPeriphery.json");

task("20220313-periphery", "Deploys and authenticates a new Periphery and a new Space Factory").setAction(
  async ({}, { ethers }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const chainId = await getChainId();
    const signer = await ethers.getSigner(deployer);

    console.log(`Deploying from ${deployer} on chain ${chainId}`);

    if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
    const balancerVault = BALANCER_VAULT.get(chainId);

    const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    const poolManager = new ethers.Contract(mainnet.poolManager, poolManagerAbi, signer);
    const oldPeriphery = new ethers.Contract(mainnet.oldPeriphery, oldPeripheryAbi, signer);

    console.log("\n-------------------------------------------------------");
    console.log("\nDeploy Space Factory");
    const queryProcessor = await deploy("QueryProcessor", {
      from: deployer,
    });

    // 1 / 10 years in seconds
    const TS = ethers.utils.parseEther("1").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("316224000"));
    // 5% of implied yield for selling Target
    const G1 = ethers.utils.parseEther("950").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("1000"));
    // 5% of implied yield for selling PTs
    const G2 = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("950"));
    const oracleEnabled = true;

    const { address: spaceFactoryAddress } = await deploy("SpaceFactory", {
      from: deployer,
      args: [balancerVault, divider.address, TS, G1, G2, oracleEnabled],
      libraries: {
        QueryProcessor: queryProcessor.address,
      },
      log: true,
    });

    const spaceFactory = new ethers.Contract(spaceFactoryAddress, spaceFactoryAbi, signer);

    console.log("\nAdding admin multisig as admin on Space Factory");
    await spaceFactory.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());

    console.log("\nRemoving deployer as admin on Space Factory");
    await spaceFactory.setIsTrusted(deployer, false).then(t => t.wait());

    console.log("\n-------------------------------------------------------");
    console.log("\nDeploy Periphery");
    const { address: peripheryAddress } = await deploy("Periphery", {
      from: deployer,
      args: [divider.address, poolManager.address, spaceFactory.address, balancerVault],
      log: true,
    });

    console.log("\nVerifying pre-approved adapters on Periphery");
    const adaptersOnboarded = (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterOnboarded(null))).map(
      e => e.args.adapter,
    );
    console.log("Adapter to onborad:", adaptersOnboarded);

    const adaptersVerified = (await oldPeriphery.queryFilter(oldPeriphery.filters.AdapterVerified(null))).map(
      e => e.args.adapter,
    );
    console.log("Adapter to verify:", adaptersVerified);

    const newPeriphery = new ethers.Contract(peripheryAddress, newPeripheryAbi, signer);

    for (let adapter of adaptersOnboarded) {
      console.log("Onboarding adapter", adapter);
      await newPeriphery.onboardAdapter(adapter, false).then(t => t.wait());
    }

    for (let adapter of adaptersOnboarded) {
      console.log("Verifying adapter", adapter);
      await newPeriphery.verifyAdapter(adapter, false).then(t => t.wait());
    }

    console.log("\nAdding admin multisig as admin on Periphery");
    await newPeriphery.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());

    console.log("\nRemoving deployer as admin on Periphery");
    await newPeriphery.setIsTrusted(deployer, false).then(t => t.wait());

    // If we're in a forked environment, check the txs we need to send from the multisig as well
    if (chainId === "111") {
      console.log("\n-------------------------------------------------------");
      console.log("\nChecking multisig txs by impersonating the address");
      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });
      const signer = await hre.ethers.getSigner(senseAdminMultisigAddress);

      const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
      const poolManager = new ethers.Contract(mainnet.poolManager, poolManagerAbi, signer);
      const oldSpaceFactory = new ethers.Contract(mainnet.oldSpaceFactory, spaceFactoryAbi, signer);
      const oldPeriphery = new ethers.Contract(mainnet.oldPeriphery, oldPeripheryAbi, signer);

      console.log("\nUnset the multisig as an authority on the old Space Factory");
      await (await oldSpaceFactory.setIsTrusted(senseAdminMultisigAddress, false)).wait();

      console.log("\nUnset the multisig as an authority on the old Periphery");
      await (await oldPeriphery.setIsTrusted(senseAdminMultisigAddress, false)).wait();

      console.log("\nSet the periphery on the Divider");
      await (await divider.setPeriphery(peripheryAddress)).wait();

      console.log("\nRemove the old Periphery auth over the pool manager");
      await (await poolManager.setIsTrusted(oldPeriphery.address, false)).wait();

      console.log("\nGive the new Periphery auth over the pool manager");
      await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();

      const ptOracleAddress = await poolManager.ptOracle();
      const lpOracleAddress = await poolManager.lpOracle();

      const ptOracle = new ethers.Contract(
        ptOracleAddress,
        [
          "function setTwapPeriod(uint256 _twapPeriod) external",
          "function twapPeriod() external view returns (uint256)",
        ],
        signer,
      );

      const lpOracle = new ethers.Contract(
        lpOracleAddress,
        [
          "function setTwapPeriod(uint256 _twapPeriod) external",
          "function twapPeriod() external view returns (uint256)",
        ],
        signer,
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
  },
);
