const dayjs = require("dayjs");
const log = console.log;

module.exports = async function () {
  const divider = await ethers.getContract("Divider");
  const periphery = await ethers.getContract("Periphery");
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  log("\n-------------------------------------------------------")
  log("SPONSOR SERIES")
  log("-------------------------------------------------------")
  for (let factory of global.mainnet.FACTORIES) {
    for (let t of factory(chainId).targets) {
      const { name: targetName, series, address: targetAddress } = t;
      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const target = new ethers.Contract(targetAddress, tokenAbi, signer);
      
      log("\nEnable the Divider to move the deployer's Target for issuance");
      await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      for (let seriesMaturity of series) {
        const { address: adapterAddress, abi: adapterAbi } = global.mainnet.ADAPTERS[targetName];
        const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
        
        log("\nEnable the Periphery to move the Deployer's STAKE for Series sponsorship");
        const stakeAddress = await adapter.stake();
        const { abi: tokenAbi } = await deployments.getArtifact("Token");
        const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
        await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        
        const stakeSize = await adapter.stakeSize();
        const balance = await stake.balanceOf(deployer); // deployer's stake balance
        if (balance.lt(stakeSize)) {
          // if fork from mainnet
          if (chainId == '111' && process.env.FORK_TOP_UP) {
            await getStakeTokens(stakeAddress, tokenAbi)
          } else {
            throw Error("Not enough stake funds on wallet")
          }
        }
        log(`\nInitializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
        await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());

      }
      log("\n-------------------------------------------------------")
    }
  }

  // TODO: make it extensible to other tokens than just DAI
  async function getStakeTokens(stakeAddress) {
    const { abi } = await deployments.getArtifact("Token");
    // TODO: maybe use hardhat_setStorageAt instead?
    const DAI_HOLDER_ADDRESS = "0x1e3d6eab4bcf24bcd04721caa11c478a2e59852d"; // account with DAI balance
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [DAI_HOLDER_ADDRESS], 
    });
    const signer = await ethers.getSigner(DAI_HOLDER_ADDRESS);
    const stake = new ethers.Contract(stakeAddress, abi, signer);
    await stake.transfer(deployer, ethers.utils.parseEther("10000")).then(tx => tx.wait()); // 10'000 DAI
    log(`\n10'000 ${await stake.symbol()} transferred to deployer: ${deployer}`);
  }
};

module.exports.tags = ["prod:series", "scenario:prod"];
module.exports.dependencies = ["prod:factories"];
