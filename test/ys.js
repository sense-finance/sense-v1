const { expect } = require("chai");
const {
  ethers,
  deployments,
  getNamedAccounts,
  getUnnamedAccounts,
} = require("hardhat");

beforeEach(async () => {
  await deployments.fixture(["ys"]);
});

describe("Yield Space", function () {
  describe("Deployment", function () {
    it("Sanity check", async function () {
      // This test expects the owner variable stored in the contract to be equal to our configured owner
      const { deployer } = await getNamedAccounts();
      const signer = await ethers.getSigner(deployer);

      const ts = ethers.utils
        .parseEther("1")
        .div(ethers.BigNumber.from(315576000));

      const g1 = ethers.utils
        .parseEther("1")
        .mul(100)
        .mul(ethers.utils.parseEther("1"))
        .div(ethers.utils.parseEther("1").mul(95));
      const g2 = ethers.utils
        .parseEther("1")
        .mul(95)
        .mul(ethers.utils.parseEther("1"))
        .div(ethers.utils.parseEther("1").mul(100));

      console.log(ts.toString(), "ts");
      console.log(g1.toString(), "ts");
      console.log(g2.toString(), "ts");

      //   uint256 ts = FixedPointMathLib.WAD.fdiv(FixedPointMathLib.WAD * 315576000, FixedPointMathLib.WAD);

      const ys = await ethers.getContract("YS");

      const poolId = await ys._poolId();

      const { abi: vaultAbi } = await deployments.getArtifact("IVault");

      console.log(vaultAbi, "vaultAbi");
      const vault = new ethers.Contract(global.MAINNET_VAULT, vaultAbi, signer);

      expect(
        await vault
          .joinPool(poolId, deployer, ethers.constants.AddressZero, {
            assets: [],
            maxAmountsIn: [],
            fromInternalBalance: false,
            userData: "0x",
          })
          .then((tx) => tx.wait())
      ).to.be.revertedWith("BAL#527");
      //   await ys.zeroIn(1, 100).then(tx => tx.wait())

      expect(true).to.equal(false);
    });
  });
});
