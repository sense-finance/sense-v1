// Hardhat tasks for interacting with deployed contracts
// Usage: npx hardhat <task> --arg <value>

const { task } = require("hardhat/config");
const fs = require("fs");

task("accounts", "Prints the list of accounts", async (_, { ethers }) => {
  const signers = await ethers.getSigners();

  for (const signer of signers) {
    console.log(signer.address);
  }
});

task("localhost-faucet", "Sends the provided address ETH and Target")
  .addParam("port", "The port number to run against")
  .addParam("contractsPath", "Path to the deployed contract export data")
  .addParam("address", "The account's address")
  .setAction(async ({ address, port, contractsPath }, { ethers }) => {
    console.log(contractsPath, "contractPath");
    const deployment = JSON.parse(fs.readFileSync(`${contractsPath}`, "utf8"));
    const { contracts } = deployment;

    if (!contracts) {
      throw new Error("Unable to find contracts at given path");
    }

    const testchainProvider = new ethers.providers.JsonRpcProvider(`http://localhost:${port}/`);
    const signer = ethers.Wallet.fromMnemonic(process.env.MNEMONIC).connect(testchainProvider);

    const ethToTransfer = ethers.utils.parseEther("5");

    console.log(`Transferring ${ethToTransfer} ETH to ${address}`);
    await signer
      .sendTransaction({
        to: address,
        value: ethToTransfer,
      })
      .then(tx => tx.wait());

    const targetToMint = ethers.utils.parseEther("100");

    for (let targe of global.dev.TARGETS) {
      const { name } = targe;
      const tokenContract = new ethers.Contract(
        contracts[name].address,
        ["function mint(address,uint256) external"],
        signer,
      );

      console.log(`Minting ${targetToMint} ${name} to ${address}`);
      await tokenContract.mint(address, targetToMint).then(tx => tx.wait());
    }
  });
