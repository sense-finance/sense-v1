const { task } = require("hardhat/config");
const { mainnet } = require("./input");

const { BALANCER_VAULT } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const spaceFactoryAbi = require("./abi/SpaceFactory.json");
const poolManagerAbi = require("./abi/PoolManager.json");
const peripheryAbi = require("./abi/Periphery.json");

// # Space

// - `deployer` – Deploy a new Space Factory with the same params as the prev deployment
// - `deployer` – Set the `multisig` as an authority on the new Space Factory
// - `deployer` – Remove the `deployer` as an authority on the new Space Factory
// - `multisig` – Remove `multisig` as an authority on the old Space Factory

// # Periphery

// - `deployer` – Deploy a new periphery with the same params as the previous deployment, except with the newly deployed Space Factory
// - `deployer` – Verify adapters on the new Periphery that are currently verified on the v1.0.0 Periphery, but don’t re-add the Target Fuse pools (call `verifyAdapter` with the second param as `false`)
// - `deployer` – Set the `multisig` as an authority on the new Periphery
// - `deployer` – Remove the `deployer` as an authority on the new Periphery
// - `multisig` – Remove the v1.0.0 Periphery as an authority from the Pool Manager
// - `multisig` – Add new periphery authority on the Pool Manager
// - `multisig` – Remove `multisig` as an authority over the v1.0.0 Periphery
// - `multisig` – Set the new periphery on the Divider

task("20220313-periphery", "Deploys and authenticates a new Periphery and a new Space Factory").setAction(
  async ({}, { ethers }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const signer = await ethers.getSigner(deployer);

    if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
    const balancerVault = BALANCER_VAULT.get(chainId);

    const divider = new ethers.Contract(mainnet.divider, dividerAbi, signer);
    const poolManager = new ethers.Contract(mainnet.poolManager, poolManagerAbi, signer);

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

    const periphery = new ethers.Contract(peripheryAddress, peripheryAbi, signer);

    console.log("Verifying pre-approved adapters on Periphery");

    console.log("Adding admin multisig as admin on Periphery");
    await periphery.setIsTrusted(mainnet.senseAdminMultisig, true).then(t => t.wait());
    console.log("Removing deployer as admin on Periphery");
    await spaceFactory.setIsTrusted(deployer, false).then(t => t.wait());

    // log("Set the periphery on the Divider");
    // await (await divider.setPeriphery(peripheryAddress)).wait();

    // log("Give the periphery auth over the pool manager");
    // await (await poolManager.setIsTrusted(peripheryAddress, true)).wait();
  },
);
