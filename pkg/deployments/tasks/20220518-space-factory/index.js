const { task } = require("hardhat/config");
const { mainnet } = require("./input");
const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekOfYear = require("dayjs/plugin/weekOfYear");

dayjs.extend(weekOfYear);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

const { SENSE_MULTISIG, BALANCER_VAULT } = require("../../hardhat.addresses");

const dividerAbi = require("./abi/Divider.json");
const oldSpaceFactoryAbi = require("./abi/OldSpaceFactory.json");
const spaceFactoryAbi = require("./abi/SpaceFactory.json");

task("20220518-space-factory", "Deploys long term wstETH adapter").setAction(async ({}, { ethers }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const deployerSigner = await ethers.getSigner(deployer);

  let divider = new ethers.Contract(mainnet.divider, dividerAbi);
  let oldSpaceFactory = new ethers.Contract(mainnet.oldSpaceFactory, oldSpaceFactoryAbi);

  console.log(`Deploying from ${deployer} on chain ${chainId}`);
  console.log("\n-------------------------------------------------------");

  if (!BALANCER_VAULT.has(chainId)) throw Error("No balancer vault found");
  const balancerVault = BALANCER_VAULT.get(chainId);

  const queryProcessor = await deploy("QueryProcessor", {
    from: deployer,
  });

  // 1 / 12 years in seconds
  const TS = ethers.utils.parseEther("1").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("379468800"));
  // 5% of implied yield for selling Target
  const G1 = ethers.utils.parseEther("950").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("1000"));
  // 5% of implied yield for selling PTs
  const G2 = ethers.utils.parseEther("1000").mul(ethers.utils.parseEther("1")).div(ethers.utils.parseEther("950"));
  const oracleEnabled = true;

  console.log("\nDeploy Space Factory");
  const { address: spaceFactoryAddress } = await deploy("SpaceFactory", {
    from: deployer,
    args: [balancerVault, divider.address, TS, G1, G2, oracleEnabled],
    libraries: {
      QueryProcessor: queryProcessor.address,
    },
    log: true,
  });

  console.log(`Space Factory deployed to ${spaceFactoryAddress}`);

  divider = divider.connect(deployerSigner);
  oldSpaceFactory = oldSpaceFactory.connect(deployerSigner);

  const sponsoredSeries = (
    await divider.queryFilter(divider.filters.SeriesInitialized(null, null, null, null, null, null))
  ).map(series => ({ adapter: series.args.adapter, maturity: series.args.maturity.toString() }));

  let spaceFactory = new ethers.Contract(spaceFactoryAddress, spaceFactoryAbi);
  spaceFactory = spaceFactory.connect(deployerSigner);

  for (let { adapter, maturity } of sponsoredSeries) {
    const pool = await oldSpaceFactory.pools(adapter, maturity);
    console.log(`Adding ${adapter} ${maturity} Series with pool ${pool} to new Space Factory pools mapping`);
    await spaceFactory.setPool(adapter, maturity, pool).then(t => t.wait());
  }
});
