const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const { SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const peripheryAbi = require("./abi/Periphery.json");
const { verifyOnEtherscan } = require("../../hardhat.utils");

task("20220914-noop-pool-manager", "Deploys a no-op Pool Manager and sets it on the Periphery").setAction(
  async (_, { ethers }) => {
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const chainId = await getChainId();
    const deployerSigner = await ethers.getSigner(deployer);

    console.log(`Deploying from ${deployer} on chain ${chainId}`);

    let periphery = new ethers.Contract(mainnet.periphery, peripheryAbi, deployerSigner);

    console.log("\n-------------------------------------------------------");
    console.log("\nDeploy NoopPoolManager");

    const { address: poolManagerAddress } = await deploy("NoopPoolManager", {
      from: deployer,
      args: [],
      log: true,
    });

    console.log(`Noop Pool Manager deployed to ${poolManagerAddress}`);

    // if not hardhat fork, we try verifying on etherscan
    if (chainId !== CHAINS.HARDHAT) {
      console.log("\n-------------------------------------------------------");
      await verifyOnEtherscan(poolManagerAddress, []);
    } else {
      console.log("\n-------------------------------------------------------");
      console.log("Checking multisig txs by impersonating the address");

      if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");
      const senseAdminMultisigAddress = SENSE_MULTISIG.get(chainId);

      // load the multisig address with some ETH
      await network.provider.send("hardhat_setBalance", [
        senseAdminMultisigAddress,
        ethers.utils.parseEther("10.0").toHexString(),
      ]);

      // impersonate multisig address
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [senseAdminMultisigAddress],
      });

      const multisigSigner = await hre.ethers.getSigner(senseAdminMultisigAddress);
      periphery = periphery.connect(multisigSigner);

      console.log(`Set Noop Pool Manager on the Periphery`);
      await (await periphery.setPoolManager(poolManagerAddress)).wait();

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [senseAdminMultisigAddress],
      });

      console.log(`Sanity check deploy cETH using cFactory`);
      periphery.deployAdapter(mainnet.cFactory, mainnet.cETH, "");
      console.log(`Success!`);
    }
  },
);
