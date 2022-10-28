const { task } = require("hardhat/config");
const data = require("./input");

const { SENSE_MULTISIG, CHAINS } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const peripheryAbi = require("./abi/Periphery.json");
const adapterAbi = [
  "function scale() external view returns (uint256)",
  "function getStakeAndTarget() external view returns (address target, address stake)",
];
const erc20Abi = [
  "function symbol() external view returns (string)",
  "function decimals() external view returns (uint256)",
  "function approve(address spender, uint256 amount) public returns (bool)",
];

task("20221007-morpho-adapters", "Deploys Morpho adapters using 4626 factory").setAction(
  async (_, { ethers }) => {
    const { deployer } = await getNamedAccounts();
    const chainId = await getChainId();
    const deployerSigner = await ethers.getSigner(deployer);

    if (!SENSE_MULTISIG.has(chainId)) throw Error("No balancer vault found");

    console.log(`Deploying from ${deployer} on chain ${chainId}`);

    const {
      divider: dividerAddress,
      periphery: peripheryAddress,
      erc4626Factory: factoryAddress,
      morphoAssets,
    } = data[chainId] || data[CHAINS.MAINNET];
    let divider = new ethers.Contract(dividerAddress, dividerAbi, deployerSigner);
    let periphery = new ethers.Contract(peripheryAddress, peripheryAbi, deployerSigner);

    console.log("\n-------------------------------------------------------");
    console.log(`\nDeploy adapters:`);
    for (let asset of morphoAssets) {
      periphery = periphery.connect(deployerSigner);

      asset = new ethers.Contract(asset, erc20Abi, deployerSigner);
      const symbol = await asset.symbol();

      console.log(`\n - Onboard target ${symbol} @ ${asset.address} via factory`);
      const data = ethers.utils.defaultAbiCoder.encode(["address[]"], [[]]);
      const adapterAddress = await periphery.callStatic.deployAdapter(factoryAddress, asset.address, data);
      await (await periphery.deployAdapter(factoryAddress, asset.address, data)).wait();
      console.log(`  -> ${symbol} adapter address: ${adapterAddress}`);

      console.log(`\n - Can call scale value and check guard amount`);
      const adptr = new ethers.Contract(adapterAddress, adapterAbi, deployerSigner);
      const scale = await adptr.callStatic.scale();
      console.log(`  -> scale: ${scale.toString()}`);

      const params = await await divider.adapterMeta(adapterAddress);
      console.log(
        `  -> adapter guard: ${ethers.utils.formatUnits(
          params[2].toString(),
          await asset.decimals(),
        )} ${symbol}`,
      );
    }
  },
);
