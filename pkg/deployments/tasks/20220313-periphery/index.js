const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { BALANCER_VAULT } = require("../../hardhat.addresses");

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

    if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
    const balancerVault = BALANCER_VAULT.get(chainId);

    const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    const poolManager = new ethers.Contract(mainnet.poolManager, poolManagerAbi, signer);
    const oldPeriphery = new ethers.Contract(mainnet.oldPeriphery, oldPeripheryAbi, signer);

    log("\n-------------------------------------------------------");
    log("\nDeploy Space Factory");

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

    console.log("Adding admin multisig as admin on Space Factory");
    await spaceFactory.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());

    console.log("Removing deployer as admin on Space Factory");
    await spaceFactory.setIsTrusted(deployer, false).then(t => t.wait());

    log("\n-------------------------------------------------------");
    log("\nDeploy Periphery");
    const { address: peripheryAddress } = await deploy("Periphery", {
      from: deployer,
      args: [divider.address, poolManager.address, spaceFactory.address, balancerVault],
      log: true,
    });

    console.log("Verifying pre-approved adapters on Periphery");
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
      await newPeriphery.onboardAdapter(adapter).then(t => t.wait());
    }

    for (let adapter of adaptersOnboarded) {
      console.log("Verifying adapter", adapter);
      await newPeriphery.verifyAdapter(adapter, false).then(t => t.wait());
    }

    console.log("Adding admin multisig as admin on Periphery");
    await newPeriphery.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());

    console.log("Removing deployer as admin on Periphery");
    await newPeriphery.setIsTrusted(deployer, false).then(t => t.wait());

    // log("Set the periphery on the Divider");
    // await (await divider.setPeriphery(peripheryAddress)).wait();

    // log("Give the periphery auth over the pool manager");
    // await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
  },
);
