const { SENSE_MULTISIG, OZ_RELAYER } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deployer, dev } = await getNamedAccounts();
  const deployerSigner = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  if (!SENSE_MULTISIG.has(chainId)) throw Error("No sense multisig found");
  const multisig = chainId === "5" ? OZ_RELAYER.get("5") : SENSE_MULTISIG.get(chainId);

  let tokenHandler = await ethers.getContract("TokenHandler", deployerSigner);
  let divider = await ethers.getContract("Divider", deployerSigner);
  let poolManager = await ethers.getContract("PoolManager", deployerSigner);
  let spaceFactory = await ethers.getContract("SpaceFactory", deployerSigner);
  let periphery = await ethers.getContract("Periphery", deployerSigner);
  let emergencyStop = await ethers.getContract("EmergencyStop", deployerSigner);

  log("\n-------------------------------------------------------")
  log("\nAdd multisig as trusted address on contracts");

  log("Trust the multisig address on the token handler");
  if (!(await tokenHandler.isTrusted(multisig))) {
    await (await tokenHandler.setIsTrusted(multisig, true)).wait();
  }

  log("Trust the multisig address on the divider");
  if (!(await divider.isTrusted(multisig))) {
    await (await divider.setIsTrusted(multisig, true)).wait();
  }

  log("Trust the multisig address on the pool manager");
  if (!(await poolManager.isTrusted(multisig))) {
    await (await poolManager.setIsTrusted(multisig, true)).wait();
  }

  log("Trust the multisig address on the space factory");
  if (!(await spaceFactory.isTrusted(multisig))) {
    await (await spaceFactory.setIsTrusted(multisig, true)).wait();
  }

  log("Trust the multisig address on the periphery");
  if (!(await periphery.isTrusted(multisig))) {
    await (await periphery.setIsTrusted(multisig, true)).wait();
  }

  log("Trust the multisig address on the emergency stop");
  if (!(await emergencyStop.isTrusted(multisig))) {
    await (await emergencyStop.setIsTrusted(multisig, true)).wait();
  }

  // if multisig is same as deployer, we don't want to untrust it
  if (multisig !== deployer) {
    log("\n-------------------------------------------------------")
    log("\nRemove deployer address from trusted on contracts");
    log("Untrust deployer on the token handler");
    if (await tokenHandler.isTrusted(deployer)) {
      await (await tokenHandler.setIsTrusted(deployer, false)).wait();  
    }

    log("Untrust deployer on the divider");
    if (await divider.isTrusted(deployer)) {
      await (await divider.setIsTrusted(deployer, false)).wait();  
    }

    log("Untrust deployer on the pool manager");
    if (await poolManager.isTrusted(deployer)) {
      await (await poolManager.setIsTrusted(deployer, false)).wait();  
    }

    log("Untrust deployer on the space factory");
    if (await spaceFactory.isTrusted(deployer)) {
      await (await spaceFactory.setIsTrusted(deployer, false)).wait();  
    }

    log("Untrust deployer on the periphery");
    if (await periphery.isTrusted(deployer)) {
      await (await periphery.setIsTrusted(deployer, false)).wait();  
    }

    log("Untrust deployer on the emergency stop");
    if (await emergencyStop.isTrusted(deployer)) {
      await (await emergencyStop.setIsTrusted(deployer, false)).wait();  
    }

    log("\n-------------------------------------------------------")
    log("\Sanity checks: checking deployer address cannot execute trusted functions anymore...");

    const calls = [
      tokenHandler.callStatic.setIsTrusted(dev, false),
      divider.callStatic.setIsTrusted(dev, false),
      poolManager.callStatic.setIsTrusted(dev, false),
      spaceFactory.callStatic.setIsTrusted(dev, false),
      periphery.callStatic.setIsTrusted(dev, false),
      emergencyStop.callStatic.setIsTrusted(dev, false),
    ];
    const res = await Promise.allSettled(calls);
    if (res.every(r => r.status === 'rejected')) {
      log("\Sanity checks: OK!");
    } else {
      throw Error('Sanity checks: FAILED');
    }
  }

  log("\n-------------------------------------------------------");
  log("Sanity checks: multisig address can execute trusted functions...");

  const multisigSigner = await hre.ethers.getSigner(multisig);
  tokenHandler = tokenHandler.connect(multisigSigner);
  divider = divider.connect(multisigSigner);
  poolManager = poolManager.connect(multisigSigner);
  spaceFactory = spaceFactory.connect(multisigSigner);
  periphery = periphery.connect(multisigSigner);
  emergencyStop = emergencyStop.connect(multisigSigner);

  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [multisig],
  });

  const calls = [
    tokenHandler.callStatic.setIsTrusted(dev, false),
    divider.callStatic.setIsTrusted(dev, false),
    poolManager.callStatic.setIsTrusted(dev, false),
    spaceFactory.callStatic.setIsTrusted(dev, false),
    periphery.callStatic.setIsTrusted(dev, false),
    emergencyStop.callStatic.setIsTrusted(dev, false),
  ];
  const res = await Promise.allSettled(calls);
  if (res.every(r => r.status === "fulfilled")) {
    log("Sanity checks: OK!");
  } else {
    throw Error("Sanity checks: FAILED");
  }

};

module.exports.tags = ["simulated:multisig", "scenario:simulated"];
module.exports.dependencies = ["simulated:series"];
