const dayjs = require("dayjs");
const { BALANCER_VAULT } = require("../../hardhat.addresses");

const ONE_MINUTE_MS = 60 * 1000;
const ONE_DAY_MS = 24 * 60 * ONE_MINUTE_MS;
const ONE_YEAR_SECONDS = (365 * ONE_DAY_MS) / 1000;

module.exports = async function ({ ethers, getNamedAccounts }) {
  const divider = await ethers.getContract("Divider");
  const periphery = await ethers.getContract("Periphery");
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  const signer = await ethers.getSigner(deployer);

  for (let factory of global.mainnet.FACTORIES) {
    for (let t of factory(chainId).targets) {
      const { name: targetName, series, address: targetAddress } = t;
      const { abi: tokenAbi } = await deployments.getArtifact("Token");
      const target = new ethers.Contract(targetAddress, tokenAbi, signer);
    
      console.log("Enable the Divider to move the deployer's Target for issuance");
      await target.approve(divider.address, ethers.constants.MaxUint256).then(tx => tx.wait());

      for (let seriesMaturity of series) {
        const { address: adapterAddress, abi: adapterAbi } = global.mainnet.ADAPTERS[targetName];
        const adapter = new ethers.Contract(adapterAddress, adapterAbi, signer);
        
        console.log("Enable the Periphery to move the Deployer's STAKE for Series sponsorship");
        const stakeAddress = await adapter.stake();
        const { abi: tokenAbi } = await deployments.getArtifact("Token");
        const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
        await stake.approve(periphery.address, ethers.constants.MaxUint256).then(tx => tx.wait());
        
        // if fork from mainnet
        if (chainId == '111') {
          // TODO: maybe use hardhat_setStorageAt instead?
          const DAI_HOLDER_ADDRESS = "0x1e3d6eab4bcf24bcd04721caa11c478a2e59852d"; // account with DAI balance
          await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [DAI_HOLDER_ADDRESS], 
          });
          const signer = await ethers.getSigner(DAI_HOLDER_ADDRESS);
          const stake = new ethers.Contract(stakeAddress, tokenAbi, signer);
          await stake.transfer(deployer, ethers.utils.parseEther("10000")).then(tx => tx.wait()); // 10'000 DAI
        }
        
        console.log(`Initializing Series maturing on ${dayjs(seriesMaturity * 1000)} for ${targetName}`);
        await periphery.sponsorSeries(adapter.address, seriesMaturity, true).then(tx => tx.wait());
      }
    }
  }
};

module.exports.tags = ["prod:series", "scenario:prod"];
module.exports.dependencies = ["prod:factories"];
