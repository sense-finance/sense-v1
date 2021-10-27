const { task } = require("hardhat/config");

task("accounts", "Prints the list of accounts", async (_, { ethers }) => {
  const signers = await ethers.getSigners();

  for (const signer of signers) {
    console.log(signer.address);
  }
});

task("fill-eth", "Prints the list of accounts", async (_, { ethers, deploy }) => {
  const [signer] = await ethers.getSigners();

  const user = process.env.DEV_ADDRESS;
  if (!user) {
    console.log(`DEV_ADDRESS must be set with an address to fill`);
    return;
  }
  console.log(`Minting ${user} 10 eth`);
  const tx = await signer.sendTransaction({
    to: user,
    value: ethers.utils.parseEther("10.0"),
  });

  await tx.wait();

  console.log("balance", await signer.getBalance(user));
});
