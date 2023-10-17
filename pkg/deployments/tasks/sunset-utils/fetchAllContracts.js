const fs = require("fs");
const axios = require("axios");
const path = require("path");
const { SENSE_ADMIN_ADDRESSES } = require("./helpers");

(async () => {
  let allContracts = {};
  for (const key of Object.keys(SENSE_ADMIN_ADDRESSES)) {
    console.log(`- Contracts deployed by ${SENSE_ADMIN_ADDRESSES[key]} -`);
    allContracts[SENSE_ADMIN_ADDRESSES[key]] = await getDeployedContracts(SENSE_ADMIN_ADDRESSES[key]);
  }

  createContractsFile(allContracts);

  /// HELPERS ///
  async function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async function getContractsDeployedByAddress(address, isContract) {
    await delay(5000); // Etherscan API rate limit (5 req/sec
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
        contractAddresses = transactions
          .filter(
            tx =>
              tx.isError === "0" &&
              (tx.type === "create" || tx.type === "create2") &&
              tx.contractAddress !== address,
          )
          .map(tx => tx.contractAddress);
      } else {
        contractAddresses = transactions
          .filter(
            tx => tx.to === "" || tx.to === null || tx.to === "0x0000000000000000000000000000000000000000",
          )
          .map(tx => tx.contractAddress);
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

  function createContractsFile(contracts) {
    const jsonString = JSON.stringify(contracts);
    const filePath = path.join(__dirname, `contracts.json`);
    fs.writeFileSync(filePath, jsonString);
    console.log("Contracts JSON file created");
  }
})();
