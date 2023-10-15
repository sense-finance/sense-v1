const { task } = require("hardhat/config");
const data = require("./input");
const fs = require("fs");
const axios = require("axios");

const { CHAINS } = require("../../hardhat.addresses");
const { fund, boostedGasPrice, zeroAddress, stopPrank } = require("../../hardhat.utils");
const { startPrank } = require("../../hardhat.utils");

task("20231031-sunset", "Sunsets Sense v1").setAction(async (_, { ethers }) => {
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  const isFork = chainId == CHAINS.HARDHAT;
  console.log(`Deploying from ${deployer} on chain ${chainId}\n`);

  const SENSE_ADMIN_ADDRESSES = {
    deployer: "0x59a181710f926eae6fddfbf27a14259e8dd00ca2".toLowerCase(), // (Ethereum) → deployer
    faucet: "0xf13519734649f7464e5be4aa91987a35594b2b16".toLowerCase(), // (Ethereum) → deployer/faucet
    relayer: "0xe09fe5acb74c1d98507f87494cf6adebd3b26b1e".toLowerCase(), // (Ethereum) → relayer
    multisig: "0xdd76360c26eaf63afcf3a8d2c0121f13ae864d57".toLowerCase(), // (Ethereum) → multisig (used as rewards recipient)
  };

  if (isFork) await startPrank(SENSE_ADMIN_ADDRESSES.multisig);

  // signers
  const multisigSigner = await ethers.getSigner(SENSE_ADMIN_ADDRESSES.multisig);
  const deployerSigner = await ethers.getSigner(deployer);

  // contracts
  const { abi: dividerAbi } = await deployments.getArtifact("Divider");
  const { abi: rlvFactoryAbi } = await deployments.getArtifact("AutoRollerFactory");
  const { abi: rlvAbi } = await deployments.getArtifact("AutoRoller");
  const { abi: adapterAbi } = await deployments.getArtifact("BaseAdapter");
  const { abi: extractableRewardAbi } = await deployments.getArtifact("ExtractableReward");
  const { abi: trustAbi } = await deployments.getArtifact("Trust");

  const { divider: dividerAddress, rlvFactory: rlvFactoryAddress } = data[chainId] || data[CHAINS.MAINNET];

  let divider = new ethers.Contract(dividerAddress, dividerAbi, multisigSigner);
  let rlvFactory = new ethers.Contract(rlvFactoryAddress, rlvFactoryAbi, multisigSigner);

  const SET_IS_TRUSTED_DATA = divider.interface.encodeFunctionData("setIsTrusted", [
    SENSE_ADMIN_ADDRESSES.multisig,
    false,
  ]);

  let multisigTxs = []; // store all multisig txs to create a JSON
  const rlvs = [
    ...new Set(
      (await rlvFactory.queryFilter(rlvFactory.filters.RollerCreated(null))).map(e => e.args.autoRoller),
    ),
  ];

  // Fund multisig
  if (isFork) await fund(deployerSigner, SENSE_ADMIN_ADDRESSES.multisig, ethers.utils.parseEther("1"));

  // (1). Turn permissionless mode ON
  if (!(await divider.permissionless())) {
    await divider.setPermissionless(true, { gasPrice: boostedGasPrice() }).then(t => t.wait());
    multisigTxs.push(
      getTx(
        dividerAddress,
        "setPermissionless",
        divider.interface.encodeFunctionData("setPermissionless", [true]),
      ),
    );
    console.log(`- Permissionless mode turned ON`);
  } else {
    console.log(`- Skipped as permissionless mode is already ON`);
  }

  let allContracts = {};
  for (const key of Object.keys(SENSE_ADMIN_ADDRESSES)) {
    console.log(`- Contracts deployed by ${SENSE_ADMIN_ADDRESSES[key]} -`);
    allContracts[SENSE_ADMIN_ADDRESSES[key]] = await getDeployedContracts(SENSE_ADMIN_ADDRESSES[key]);
  }

  // (2). For each contract, we want to remove us as reward recipients and remove us as trusted addresses
  for (const address of Object.keys(allContracts)) {
    for (const contract of allContracts[address]) {
      console.log(`\n- Processing contract ${contract.address} -`);
      await removeRewardsRecipient(contract.address);
      // if (await isRLV(contract.address)) await disableAdapter(contract.address); // do we want to disable the adapter is it's an RLV?
      await removeTrust(contract.address);
    }
  }

  // (3). Show functions to execute from multisig
  console.log(`\n------- TOTAL ADMIN TRANSACTIONS TO EXECUTE: ${multisigTxs.length} -------`);
  console.log(`------------------------------------------------------------------`);
  for (let i = 0; i < multisigTxs.length; i++) {
    console.log(`   (${i}). to: ${multisigTxs[i].to} - data: ${multisigTxs[i].data}`);
  }
  multisigTxs.forEach(tx => {
    delete tx.method;
  });

  // TODO: check how to generate the meta data, otherwise we will have to manually input each tx on the
  // Gnosis UI Builder
  const file = {
    version: "1.0",
    chainId: "1",
    createdAt: 1697220810745,
    meta: {
      name: "Transactions Batch",
      description: "",
      txBuilderVersion: "1.16.3",
      createdFromSafeAddress: "0xDd76360C26Eaf63AFCF3a8d2c0121F13AE864D57",
      createdFromOwnerAddress: "",
      checksum: "",
      transactions: multisigTxs,
    },
  };
  const jsonString = JSON.stringify(file);
  fs.writeFileSync("./multisigTxs.json", jsonString);
  console.log("Transactions JSON file created");
  const multisend = "0x38869bf66a61cF6bDB996A6aE40D5853Fd43B526";

  /// UTILS ///

  async function isRLV(adapter) {
    let roller = false;
    for (const rlvAddress of rlvs) {
      const rlv = new ethers.Contract(rlvAddress, rlvAbi, deployerSigner);
      if ((await rlv.adapter()).toLowerCase() === adapter.toLowerCase()) {
        roller = true;
        break;
      }
    }
    return roller;
  }

  async function removeRewardsRecipient(address) {
    let contract = new ethers.Contract(address, extractableRewardAbi, multisigSigner);

    // check if contract is ExtractableReward.sol
    try {
      await contract.rewardsRecipient();
    } catch (e) {
      console.log(`   * Is not an extractable contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    if (trusted.sense.length > 1) {
      throw new Error(`   * More than one trusted address: ${trusted.sense}`);
    }

    // set reward recipient to zero address
    if (Object.values(SENSE_ADMIN_ADDRESSES).includes((await contract.rewardsRecipient()).toLowerCase())) {
      // some contracts were never changed to be trusted by the multisig and remained trusted by the deployer
      if (!(await contract.isTrusted(SENSE_ADMIN_ADDRESSES.multisig))) {
        contract = contract.connect(deployerSigner);
      } else {
        await contract
          .setRewardsRecipient(zeroAddress(), { gasPrice: boostedGasPrice() })
          .then(t => t.wait());
        multisigTxs.push(
          getTx(
            address,
            "setRewardsRecipient",
            contract.interface.encodeFunctionData("setRewardsRecipient", [zeroAddress()]),
          ),
        );
      }
      console.log(`   * Rewards recipient set to zero address`);
    } else {
      console.log(`   * Rewards recipient is already zero address`);
    }
  }

  // make sure there are no more sense addresses trusted
  async function removeTrust(address) {
    let contract = new ethers.Contract(address, trustAbi, multisigSigner);

    // check if contract is Trust.sol
    try {
      await contract.isTrusted(SENSE_ADMIN_ADDRESSES.multisig);
    } catch (e) {
      console.log(`   * Is not a trust contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    if (trusted.sense.length === 0) {
      console.log(`   * No trusted addresses`);
      return;
    }
    // if deployer is trusted, we can call setIsTrusted for all the addresses directly from this script
    const includesDeployer = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.deployer.toLowerCase());
    if (includesDeployer) contract = contract.connect(deployerSigner);
    if (isFork && includesDeployer) await stopPrank(SENSE_ADMIN_ADDRESSES.multisig); // stop pranking

    for (const address of trusted.sense) {
      if (includesDeployer && address === SENSE_ADMIN_ADDRESSES.deployer.toLowerCase()) continue;
      if (!includesDeployer && address === SENSE_ADMIN_ADDRESSES.multisig.toLowerCase()) continue;

      await contract.setIsTrusted(address, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());

      if (address.toLowerCase() === SENSE_ADMIN_ADDRESSES.multisig.toLowerCase()) {
        multisigTxs.push(getTx(contract.address, "setIsTrusted", SET_IS_TRUSTED_DATA));
      }
    }

    // last call with corresponding remaining address
    if (includesDeployer) {
      await contract
        .setIsTrusted(SENSE_ADMIN_ADDRESSES.deployer, false, { gasPrice: boostedGasPrice() })
        .then(t => t.wait());
    } else {
      await contract
        .setIsTrusted(SENSE_ADMIN_ADDRESSES.multisig, false, { gasPrice: boostedGasPrice() })
        .then(t => t.wait());
      multisigTxs.push(getTx(contract.address, "setIsTrusted", SET_IS_TRUSTED_DATA));
    }
    console.log(`   * ${address} is no longer trusted`);

    if (trusted.other.length > 0) console.log(`   * Other trusted addresses: ${trusted.other}`); // log other trusted addresses
    if (isFork && includesDeployer) await startPrank(SENSE_ADMIN_ADDRESSES.multisig); // re-start pranking
  }

  async function getTrustedAddresses(contract) {
    const trustedAddresses = [
      ...new Set(
        (await contract.queryFilter(contract.filters.UserTrustUpdated(null))).map(e =>
          e.args.user.toLowerCase(),
        ),
      ),
    ];
    // if (trustedAddresses.length > 0) console.log(`   * Trusted addresses: ${trustedAddresses}`)

    const senseTrustedAddresses = await asyncFilter(
      trustedAddresses,
      async a =>
        Object.values(SENSE_ADMIN_ADDRESSES).includes(a.toLowerCase()) && (await contract.isTrusted(a)),
    );
    // if (senseTrustedAddresses.length > 0) console.log(`   * Sense trusted addresses: ${senseTrustedAddresses}`);

    const otherTrustedAddresses = await asyncFilter(
      trustedAddresses,
      async a =>
        !Object.values(SENSE_ADMIN_ADDRESSES).includes(a.toLowerCase()) && (await contract.isTrusted(a)),
    );
    // if (otherTrustedAddresses.length > 0) console.log(`   * Sense trusted addresses: ${otherTrustedAddresses}`);

    return {
      all: trustedAddresses,
      sense: senseTrustedAddresses,
      other: otherTrustedAddresses,
    };
  }

  async function getContractsDeployedByAddress(address, isContract) {
    const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
    try {
      const etherscanUrl = `https://api.etherscan.io/api?`;
      const response = await axios.get(etherscanUrl, {
        params: {
          module: "account",
          action: isContract ? "txlistinternal" : "txlist",
          address,
          sort: "asc",
          apikey: ETHERSCAN_API_KEY,
        },
      });

      let contractAddresses;
      const transactions = response.data.result;
      if (isContract) {
        contractAddresses = await Promise.all(
          transactions
            .filter(tx => tx.isError === "0" && tx.type === "create" && tx.contractAddress !== address)
            .map(async tx => {
              return {
                address: tx.contractAddress,
                // name: await getContractName(tx.contractAddress)
              };
            }),
        );
      } else {
        contractAddresses = await Promise.all(
          transactions
            .filter(
              tx => tx.to === "" || tx.to === null || tx.to === "0x0000000000000000000000000000000000000000",
            )
            .map(async tx => {
              return {
                address: tx.contractAddress,
                // name: await getContractName(tx.contractAddress)
              };
            }),
        );
      }

      return contractAddresses;
    } catch (error) {
      console.error(error);
      return null;
    }
  }

  async function getDeployedContracts(address, isContract = false, indent = 0) {
    const contracts = await getContractsDeployedByAddress(address, isContract);

    // Recursively get contracts deployed by each address
    let allContracts = [];

    if (contracts.length > 0) {
      console.log(`${" ".repeat(indent)}- Contracts deployed by ${address} -`);

      for (const contract of contracts) {
        console.log(`${" ".repeat(indent + 3)}* ${contract.address} - ${contract.name || ""}`);
        allContracts.push({
          address: contract.address,
          name: contract.name,
        });
        allContracts = allContracts.concat(await getDeployedContracts(contract.address, true, indent + 3));
      }
    }

    return allContracts;
  }

  async function disableAdapter(contract) {
    let adapter = new ethers.Contract(adapterAddress, adapterAbi, multisigSigner);
    let roller = isRLV(adapterAddress);
    console.log(
      `- Contract is adapter ${await adapter.symbol()} @ ${adapterAddress} ${roller ? "(RLV)" : ""} -`,
    );

    adapter = new ethers.Contract(adapterAddress, extractableRewardAbi, multisigSigner);
    adapter = adapter.connect(multisigSigner);

    // since RLVs have a rewardsRecipient that is immutable, we will disable the adapter
    if (roller) {
      if ((await divider.adapterMeta(adapterAddress)).enabled) {
        await divider.setAdapter(adapterAddress, false, { gasPrice: boostedGasPrice() }).then(t => t.wait()); // (ADMIN ACTION)
        multisigTxs.push(
          getTx(
            dividerAddress,
            "setAdapter",
            divider.interface.encodeFunctionData("setAdapter", [adapterAddress, false]),
          ),
        );
        console.log(`   * Adapter marked as disabled on divider`);
      } else {
        console.log(`   * Adapter is already disabled on divider`);
      }
    }
  }

  async function getContractName(address) {
    await delay(200); // Introducing a delay of 200ms to stay under rate limit
    const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
    const etherscanUrl = `https://api.etherscan.io/api?`;
    const response = await axios.get(etherscanUrl, {
      params: {
        module: "contract",
        action: "getsourcecode",
        address,
        apikey: ETHERSCAN_API_KEY,
      },
    });
    return response.data.result[0].ContractName;
  }
});

const asyncFilter = async (arr, predicate) =>
  Promise.all(arr.map(predicate)).then(results => arr.filter((_v, index) => results[index]));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const getTx = (to, method, data) => {
  return {
    to,
    value: "0",
    data,
    method,
    operation: "1",
    contractMethod: null,
    contractInputsValues: null,
  };
};
