const { task } = require("hardhat/config");
const data = require("./input");
const fs = require("fs");
const axios = require("axios");
const web3 = require("web3");
const path = require("path");

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

  // ABIs
  const { abi: dividerAbi } = await deployments.getArtifact("Divider");
  const { abi: extractableRewardAbi } = await deployments.getArtifact("ExtractableReward");
  const { abi: trustAbi } = await deployments.getArtifact("Trust");
  // const { abi: rlvAbi } = await deployments.getArtifact("AutoRoller");

  // divider
  const { divider: dividerAddress } = data[chainId] || data[CHAINS.MAINNET];
  let divider = new ethers.Contract(dividerAddress, dividerAbi, multisigSigner);

  const SET_IS_TRUSTED_DATA = divider.interface.encodeFunctionData("setIsTrusted", [
    SENSE_ADMIN_ADDRESSES.multisig,
    false,
  ]);

  let multisigTxs = []; // store all multisig txs to create a JSON

  // Fund multisig
  if (isFork) await fund(deployerSigner, SENSE_ADMIN_ADDRESSES.multisig, ethers.utils.parseEther("1"));

  // (1). Turn permissionless mode ON
  if (!(await divider.permissionless())) {
    if (isFork) await divider.setPermissionless(true, { gasPrice: boostedGasPrice() }).then(t => t.wait());
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

  // (2). For each contract, remove us as reward recipients
  for (const address of Object.keys(allContracts)) {
    for (const contract of allContracts[address]) {
      console.log(`\n- Processing contract ${contract} -`);
      await removeRewardsRecipient(contract);
    }
  }

  await sanitiseExtractableContracts(allContracts);

  // (3). For each contract, remove us as trusted addresses
  for (const address of Object.keys(allContracts)) {
    for (const contract of allContracts[address]) {
      console.log(`\n- Processing contract ${contract} -`);
      await removeTrust(contract);
    }
  }

  await sanitiseTrustContracts(allContracts);

  // (4). Show functions to execute from multisig
  console.log(`\n------- TOTAL ADMIN TRANSACTIONS TO EXECUTE: ${multisigTxs.length} -------`);
  console.log(`------------------------------------------------------------------`);
  for (let i = 0; i < multisigTxs.length; i++) {
    console.log(`   (${i}). to: ${multisigTxs[i].to} - data: ${multisigTxs[i].data}`);
  }
  multisigTxs.forEach(tx => {
    delete tx.method;
  });

  // (5). Prepare JSON file with batched txs for Gnosis Safe Transaction Builder UI
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
    },
    transactions: multisigTxs,
  };
  file.meta.checksum = calculateChecksum(file);
  const jsonString = JSON.stringify(file);
  const filePath = path.join(__dirname, "multisigTxs.json");
  fs.writeFileSync(filePath, jsonString);
  console.log("Transactions JSON file created");

  /// HELPERS ///

  // set reward recipient to zero address
  async function removeRewardsRecipient(address) {
    let contract = new ethers.Contract(address, extractableRewardAbi, multisigSigner);

    // Check if contract is ExtractableReward.sol
    if (!(await isExtractableContract(contract))) {
      console.log(`   * Is not an extractable contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    const rewardsRecipient = (await contract.rewardsRecipient()).toLowerCase();
    const isDeployerTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.deployer);
    const isMultisigTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.multisig);

    if (Object.values(SENSE_ADMIN_ADDRESSES).includes(rewardsRecipient)) {
      contract = isDeployerTrusted ? contract.connect(deployerSigner) : contract;

      if (isFork && isDeployerTrusted) await stopPrank(SENSE_ADMIN_ADDRESSES.multisig);

      if (isFork || isDeployerTrusted) {
        await contract
          .setRewardsRecipient(zeroAddress(), { gasPrice: boostedGasPrice() })
          .then(t => t.wait());

        if (isFork) await startPrank(SENSE_ADMIN_ADDRESSES.multisig); // assuming this is how you restart the prank
      }

      if (!isDeployerTrusted && isMultisigTrusted) {
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

    // Validate if the contract has the 'isTrusted' method
    if (!(await isTrustContract(contract))) {
      console.log(`   * Is not a trust contract`);
      return;
    }

    const trusted = await getTrustedAddresses(contract);
    if (trusted.sense.length === 0) {
      console.log(`   * No trusted addresses`);
      return;
    }

    const isDeployerTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.deployer);
    const isMultisigTrusted = trusted.sense.includes(SENSE_ADMIN_ADDRESSES.multisig);
    contract = isDeployerTrusted ? contract.connect(deployerSigner) : contract;
    if (isFork && isDeployerTrusted) await stopPrank(SENSE_ADMIN_ADDRESSES.multisig);

    for (const trustAddress of trusted.sense) {
      if (isFork || isDeployerTrusted) {
        await contract.setIsTrusted(trustAddress, false, { gasPrice: boostedGasPrice() }).then(t => t.wait());
      }

      if (!isDeployerTrusted && isMultisigTrusted) {
        multisigTxs.push(getTx(contract.address, "setIsTrusted", SET_IS_TRUSTED_DATA));
      }
    }

    console.log(`   * ${address} is no longer trusted`);
    if (trusted.other.length > 0) console.log(`   * Other trusted addresses: ${trusted.other}`);
    if (isFork && isDeployerTrusted) await startPrank(SENSE_ADMIN_ADDRESSES.multisig);
  }

  async function isTrustContract(contract) {
    try {
      await contract.isTrusted(SENSE_ADMIN_ADDRESSES.multisig);
      return true;
    } catch (e) {
      return false;
    }
  }

  async function isExtractableContract(contract) {
    try {
      await contract.rewardsRecipient();
      return true;
    } catch (e) {
      return false;
    }
  }

  // iterates over the contracts and check that we are not longer a rewards recipient
  async function sanitiseExtractableContracts(allContracts) {
    for (const addresses of Object.values(allContracts)) {
      for (const contractAddress of addresses) {
        const contract = new ethers.Contract(contractAddress, extractableRewardAbi, multisigSigner);
        if (
          (await isExtractableContract(contract)) &&
          (await contract.rewardsRecipient()).toLowerCase() !== zeroAddress()
        ) {
          throw new Error(`Extractable contract ${contractAddress} is not sanitised`);
        }
      }
    }
  }

  // iterates over the contracts and check that we are not longer trusted
  async function sanitiseTrustContracts(allContracts) {
    for (const addresses of Object.values(allContracts)) {
      for (const contractAddress of addresses) {
        const contract = new ethers.Contract(contractAddress, trustAbi, multisigSigner);
        for (const address of Object.values(SENSE_ADMIN_ADDRESSES)) {
          if ((await isTrustContract(contract)) && (await contract.isTrusted(address))) {
            throw new Error(`Trust contract ${contractAddress} is not sanitised`);
          }
        }
      }
    }
  }

  async function getTrustedAddresses(contract) {
    let trustedAddresses = [
      ...new Set(
        (await contract.queryFilter(contract.filters.UserTrustUpdated(null))).map(e =>
          e.args.user.toLowerCase(),
        ),
      ),
    ];
    trustedAddresses = await asyncFilter(
      trustedAddresses,
      async a => Object.values(SENSE_ADMIN_ADDRESSES).includes(a) && (await contract.isTrusted(a)),
    );

    // if multisig is trusted, send it to the second to last position of the array
    if (trustedAddresses.length > 1 && trustedAddresses.includes(SENSE_ADMIN_ADDRESSES.multisig)) {
      trustedAddresses.push(
        trustedAddresses.splice(trustedAddresses.indexOf(SENSE_ADMIN_ADDRESSES.multisig), 1)[0],
      );
    }
    // if deployer is trusted, send it to the last position of the array
    if (trustedAddresses.length > 1 && trustedAddresses.includes(SENSE_ADMIN_ADDRESSES.deployer)) {
      trustedAddresses.push(
        trustedAddresses.splice(trustedAddresses.indexOf(SENSE_ADMIN_ADDRESSES.deployer), 1)[0],
      );
    }

    const senseTrustedAddresses = await asyncFilter(trustedAddresses, async a =>
      Object.values(SENSE_ADMIN_ADDRESSES).includes(a),
    );

    const otherTrustedAddresses = await asyncFilter(
      trustedAddresses,
      async a => !Object.values(SENSE_ADMIN_ADDRESSES).includes(a),
    );

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
            .filter(
              tx =>
                tx.isError === "0" &&
                (tx.type === "create" || tx.type === "create2") &&
                tx.contractAddress !== address,
            )
            .map(tx => tx.contractAddress),
        );
      } else {
        contractAddresses = await Promise.all(
          transactions
            .filter(
              tx => tx.to === "" || tx.to === null || tx.to === "0x0000000000000000000000000000000000000000",
            )
            .map(async tx => tx.contractAddress),
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
        console.log(`${" ".repeat(indent + 3)}* ${contract}`);
        allContracts.push(contract);
        allContracts = allContracts.concat(await getDeployedContracts(contract, true, indent + 3));
      }
    }

    return allContracts;
  }
});

// UTILS

const asyncFilter = async (arr, predicate) =>
  Promise.all(arr.map(predicate)).then(results => arr.filter((_v, index) => results[index]));
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

const stringifyReplacer = (_, value) => (value === undefined ? null : value);

const serializeJSONObject = json => {
  if (Array.isArray(json)) {
    return `[${json.map(el => serializeJSONObject(el)).join(",")}]`;
  }

  if (typeof json === "object" && json !== null) {
    let acc = "";
    const keys = Object.keys(json).sort();
    acc += `{${JSON.stringify(keys, stringifyReplacer)}`;

    for (let i = 0; i < keys.length; i++) {
      acc += `${serializeJSONObject(json[keys[i]])},`;
    }

    return `${acc}}`;
  }

  return `${JSON.stringify(json, stringifyReplacer)}`;
};

const calculateChecksum = batchFile => {
  const serialized = serializeJSONObject({
    ...batchFile,
    meta: { ...batchFile.meta },
  });
  const sha = web3.utils.sha3(serialized);

  return sha || undefined;
};
