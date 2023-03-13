const { SENSE_MULTISIG, OZ_RELAYER, CHAINS } = require("../../hardhat.addresses");
const log = console.log;

module.exports = async function () {
  const { deployer, dev } = await getNamedAccounts();
  const deployerSigner = await ethers.getSigner(deployer);
  const chainId = await getChainId();

  let signer;
  if (chainId === CHAINS.MAINNET) {
    if (!SENSE_MULTISIG.has("1")) throw Error("No sense multisig found for mainnet");
    signer = SENSE_MULTISIG.get(chainId);
  } else {
    if (!OZ_RELAYER.get(chainId)) throw Error(`No OZ relayer found for chain ID ${chainId}`);
    signer = OZ_RELAYER.get("5");
  }

  let tokenHandler = await ethers.getContract("TokenHandler", deployerSigner);
  let divider = await ethers.getContract("Divider", deployerSigner);
  let spaceFactory = await ethers.getContract("SpaceFactory", deployerSigner);
  let periphery = await ethers.getContract("Periphery", deployerSigner);
  let emergencyStop = await ethers.getContract("EmergencyStop", deployerSigner);

  log("\n-------------------------------------------------------");
  log("\nAdd signer as trusted address on contracts");

  log("Trust the signer address on the token handler");
  if (!(await tokenHandler.isTrusted(signer))) {
    await (await tokenHandler.setIsTrusted(signer, true)).wait();
  }

  log("Trust the signer address on the divider");
  if (!(await divider.isTrusted(signer))) {
    await (await divider.setIsTrusted(signer, true)).wait();
  }

  // log("Trust the signer address on the pool manager");
  // if (!(await poolManager.isTrusted(signer))) {
  //   await (await poolManager.setIsTrusted(signer, true)).wait();
  // }

  log("Trust the signer address on the space factory");
  if (!(await spaceFactory.isTrusted(signer))) {
    await (await spaceFactory.setIsTrusted(signer, true)).wait();
  }

  log("Trust the signer address on the periphery");
  if (!(await periphery.isTrusted(signer))) {
    await (await periphery.setIsTrusted(signer, true)).wait();
  }

  log("Trust the signer address on the emergency stop");
  if (!(await emergencyStop.isTrusted(signer))) {
    await (await emergencyStop.setIsTrusted(signer, true)).wait();
  }

  // if signer is same as deployer, we don't want to untrust it
  if (signer !== deployer) {
    log("\n-------------------------------------------------------");
    log("\nRemove deployer address from trusted on contracts");
    log("Untrust deployer on the token handler");
    if (await tokenHandler.isTrusted(deployer)) {
      await (await tokenHandler.setIsTrusted(deployer, false)).wait();
    }

    log("Untrust deployer on the divider");
    if (await divider.isTrusted(deployer)) {
      await (await divider.setIsTrusted(deployer, false)).wait();
    }

    // log("Untrust deployer on the pool manager");
    // if (await poolManager.isTrusted(deployer)) {
    //   await (await poolManager.setIsTrusted(deployer, false)).wait();
    // }

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

    log("\n-------------------------------------------------------");
    log("Sanity checks: checking deployer address cannot execute trusted functions anymore...");

    const calls = [
      tokenHandler.callStatic.setIsTrusted(dev, false),
      divider.callStatic.setIsTrusted(dev, false),
      spaceFactory.callStatic.setIsTrusted(dev, false),
      periphery.callStatic.setIsTrusted(dev, false),
      emergencyStop.callStatic.setIsTrusted(dev, false),
    ];
    const res = await Promise.allSettled(calls);
    if (res.every(r => r.status === "rejected")) {
      log("Sanity checks: OK!");
    } else {
      throw Error("Sanity checks: FAILED");
    }
  }

  log("\n-------------------------------------------------------");
  log("Sanity checks: signer address is a trusted address...");

  const multisigSigner = await hre.ethers.getSigner(signer);
  tokenHandler = tokenHandler.connect(multisigSigner);
  divider = divider.connect(multisigSigner);
  spaceFactory = spaceFactory.connect(multisigSigner);
  periphery = periphery.connect(multisigSigner);
  emergencyStop = emergencyStop.connect(multisigSigner);

  const calls = [
    tokenHandler.isTrusted(signer),
    divider.isTrusted(signer),
    spaceFactory.isTrusted(signer),
    periphery.isTrusted(signer),
    emergencyStop.isTrusted(signer),
  ];
  const res = await Promise.allSettled(calls);
  if (res.every(r => r.value === true)) {
    log("Sanity checks: OK!");
  } else {
    throw Error("Sanity checks: FAILED");
  }
};

module.exports.tags = ["simulated:signer", "scenario:simulated"];
module.exports.dependencies = ["simulated:emergency-stop"];
