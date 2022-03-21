// const { ethers } = require("hardhat");
// const log = console.log;

// module.exports = async function () {
//   const { deploy } = deployments;
//   const { deployer } = await getNamedAccounts();

//   const signer = await ethers.getSigner(deployer);
//   const divider = await ethers.getContract("Divider", signer);

//   log("\n-------------------------------------------------------");
//   console.log("\nDeploy mocked fuse & comp dependencies");
//   const { address: mockComptrollerAddress } = await deploy("MockComptroller", {
//     from: deployer,
//     args: [],
//     log: true,
//   });
//   const { address: mockFuseDirectoryAddress } = await deploy("MockFuseDirectory", {
//     from: deployer,
//     args: [mockComptrollerAddress],
//     log: true,
//   });
//   const { address: mockFuseOracleAddress } = await deploy("MockOracle", {
//     from: deployer,
//     args: [],
//     log: true,
//   });

//   log("\n-------------------------------------------------------");
//   console.log("\nDeploy a pool manager with mocked dependencies");
//   await deploy("PoolManager", {
//     from: deployer,
//     args: [
//       mockFuseDirectoryAddress,
//       mockComptrollerAddress,
//       ethers.constants.AddressZero,
//       divider.address,
//       mockFuseOracleAddress,
//     ],
//     log: true,
//   });

//   const poolManager = await ethers.getContract("PoolManager", signer);
//   log("\n-------------------------------------------------------");
//   console.log("\nDeploy Sense Fuse pool via Pool Manager");
//   if ((await poolManager.comptroller()) == ethers.constants.AddressZero) {
//     await (
//       await poolManager.deployPool(
//         "Sense Pool – Main",
//         ethers.utils.parseEther("0.051"),
//         ethers.utils.parseEther("1"),
//         mockFuseOracleAddress,
//       )
//     ).wait();
//   }

//   log("Set target params via Pool Manager");
//   const params = {
//     irModel: ethers.Wallet.createRandom().address,
//     reserveFactor: ethers.utils.parseEther("0.1"),
//     collateralFactor: ethers.utils.parseEther("0.5"),
//     closeFactor: ethers.utils.parseEther("0.051"),
//     liquidationIncentive: ethers.utils.parseEther("1"),
//   };
//   const { reserveFactor } = await poolManager.targetParams();
//   if (!reserveFactor.eq(ethers.utils.parseEther("0.1"))) {
//     await (await poolManager.setParams(ethers.utils.formatBytes32String("TARGET_PARAMS"), params)).wait();
//   }
// };

// module.exports.tags = ["simulated:fuse", "scenario:simulated"];
// module.exports.dependencies = ["simulated:divider"];
