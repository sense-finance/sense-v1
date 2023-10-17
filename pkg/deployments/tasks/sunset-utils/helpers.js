const fs = require("fs");
const web3 = require("web3");
const path = require("path");

const SENSE_ADMIN_ADDRESSES = {
  deployer: "0x59a181710f926eae6fddfbf27a14259e8dd00ca2".toLowerCase(), // (Ethereum) → deployer
  faucet: "0xf13519734649f7464e5be4aa91987a35594b2b16".toLowerCase(), // (Ethereum) → deployer/faucet
  relayer: "0xe09fe5acb74c1d98507f87494cf6adebd3b26b1e".toLowerCase(), // (Ethereum) → relayer
  multisig: "0xdd76360c26eaf63afcf3a8d2c0121f13ae864d57".toLowerCase(), // (Ethereum) → multisig (used as rewards recipient)
};

function printTxs(txs) {
  console.log(`\n------- TOTAL ADMIN TRANSACTIONS TO EXECUTE: ${txs.length} -------`);
  console.log(`------------------------------------------------------------------`);
  for (let i = 0; i < txs.length; i++) {
    console.log(`   (${i}). to: ${txs[i].to} - data: ${txs[i].data}`);
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

function createBatchFile(name, date, transactions) {
  const file = {
    version: "1.0",
    chainId: "1",
    createdAt: date,
    meta: {
      name,
      description: "",
      txBuilderVersion: "1.16.3",
      createdFromSafeAddress: SENSE_ADMIN_ADDRESSES.multisig,
      createdFromOwnerAddress: "",
      checksum: "",
    },
    transactions,
  };
  file.meta.checksum = calculateChecksum(file);
  const jsonString = JSON.stringify(file);
  const filePath = path.join(__dirname, `${name}.json`);
  fs.writeFileSync(filePath, jsonString);
  console.log("Transactions JSON file created");
}

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

// export functions
module.exports = {
  SENSE_ADMIN_ADDRESSES,
  getTrustedAddresses,
  createBatchFile,
  asyncFilter,
  getTx,
  stringifyReplacer,
  serializeJSONObject,
  calculateChecksum,
  printTxs,
};
