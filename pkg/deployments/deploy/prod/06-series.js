const dayjs = require("dayjs");
const { getDeployedAdapters, setStorageAt, toBytes32, STORAGE_SLOT } = require("../../hardhat.utils");
const log = console.log;

module.exports = async function () {
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);
  const divider = await ethers.getContract("Divider", signer);
  const periphery = await ethers.getContract("Periphery", signer);

  const chainId = await getChainId();

  const ADAPTER_ABI = [
    "function stake() public view returns (address)",
    "function stakeSize() public view returns (uint256)",
  ];
  const adapters = await getDeployedAdapters();

  log("\n-------------------------------------------------------")
  log("SPONSOR SERIES")
  log("-------------------------------------------------------")

  for (let factory of global.mainnet.FACTORIES) {
    for (let t of factory(chainId).targets) {
      await sponsor(t);
    }
  }

  for (let adapter of global.mainnet.ADAPTERS) {
    await sponsor(adapter(chainId).target);
  }

  async function sponsor(t) {
    const { name: targetName, series, address: targetAddress } = t;
    const { abi: tokenAbi } = await deployments.getArtifact("Token");
    const target = new ethers.Contract(targetAddress, tokenAbi, signer);

    log("\nEnable the Divider to move the deployer's Target for issuance");
    await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

    for (let seriesMaturity of series) {
      const adapter = new ethers.Contract(adapters[targetName], ADAPTER_ABI, signer);
      
      log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
      // TODO: should check allowance to avoid calling this multiple times
      const stakeAddress = await adapter.stake();
      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
      await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      const stakeSize = await adapter.stakeSize();
      const balance = await stake.balanceOf(deployer); // deployer's stake balance
      if (balance.lt(stakeSize)) {
        // if fork from mainnet
        if (chainId == '111' && process.env.FORK_TOP_UP == 'true') {
          await generateStakeTokens(stakeAddress, tokenAbi)
        } else {
          throw Error("Not enough stake funds on wallet")
        }
      }
      log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
      await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());
      log("\n-------------------------------------------------------")
    }
  }

  async function generateStakeTokens(stakeAddress) {
    const { abi } = await deployments.getArtifact("Token");
    const stake = new ethers.Contract(stakeAddress, abi, signer);
    const symbol = await stake.symbol();

    // Get storage slot index
    const index = ethers.utils.solidityKeccak256(
      ["uint256", "uint256"],
      [deployer, STORAGE_SLOT[symbol] || 2] // key, slot
    );

    await setStorageAt(
      stakeAddress,
      index.toString(),
      toBytes32(ethers.utils.parseEther("10000")).toString()
    );
    log(`\n10'000 ${symbol} transferred to deployer: ${deployer}`);
  }
};

module.exports.tags = ["prod:series", "scenario:prod"];
module.exports.dependencies = ["prod:factories"];
