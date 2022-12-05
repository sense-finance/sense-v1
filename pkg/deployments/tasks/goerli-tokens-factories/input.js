const {
  WETH_TOKEN,
  CHAINS,
  SENSE_MULTISIG,
  MORPHO_DAI,
  CUSDC_TOKEN,
  CUSDT_TOKEN,
  CDAI_TOKEN,
  DAI_TOKEN,
  USDC_TOKEN,
  REWARD_TOKEN,
  MORPHO_USDT,
  RLV_FACTORY,
  DIVIDER_1_2_0,
  PERIPHERY_1_4_0,
  BALANCER_VAULT,
  ROLLER_PERIPHERY,
  ROLLER_UTILS,
} = require("../../hardhat.addresses");
const ethers = require("ethers");

const dayjs = require("dayjs");
const utc = require("dayjs/plugin/utc");
const en = require("dayjs/locale/en");
const weekday = require("dayjs/plugin/weekday");

dayjs.extend(weekday);
dayjs.extend(utc);
dayjs.locale({
  ...en,
  weekStart: 1,
});

// next week
const MATURITIES = [dayjs().utc().weekday(7).startOf("week").unix()];

// If address is not passed, the token will be deployed and verified on Etherscan
const GOERLI_TOKENS = {
  // Underlying must always be in first place
  tokens: [
    {
      underlying: {
        contractName: "AuthdMockToken",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol:AuthdMockToken",
        name: "USDC",
        symbol: "USDC",
        decimals: 6,
        address: USDC_TOKEN.get(CHAINS.GOERLI),
      },
      target: {
        contractName: "AuthdMockTarget",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol:AuthdMockTarget",
        name: "Compound USDC",
        symbol: "cUSDC",
        decimals: 8,
        address: CUSDC_TOKEN.get(CHAINS.GOERLI),
        adapter: "0x3de1bEE160898B204D470F41a82d9Bd066CfE6a6",
      },
    },
    {
      underlying: {
        contractName: "AuthdMockToken",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol:AuthdMockToken",
        name: "Dai Stablecoin",
        symbol: "DAI",
        decimals: 18,
        address: DAI_TOKEN.get(CHAINS.GOERLI),
      },
      target: {
        contractName: "AuthdMockTarget",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol:AuthdMockTarget",
        name: "Compound DAI",
        symbol: "cDAI",
        decimals: 8,
        address: CDAI_TOKEN.get(CHAINS.GOERLI),
        adapter: "0xfcC6ba91745F0a81f2334D7608c7D2B72c9E8e84",
      },
      target4626: {
        contractName: "MockERC4626_Unique",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockERC4626.sol:MockERC4626",
        name: "Morpho-Aave Dai Stablecoin Supply Vault",
        symbol: "maDAI",
        decimals: 18,
        address: MORPHO_DAI.get(CHAINS.GOERLI),
      },
    },
    {
      underlying: {
        contractName: "AuthdMockToken",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol:AuthdMockToken",
        name: "Tether USDT",
        symbol: "USDT",
        decimals: 6,
        address: USDC_TOKEN.get(CHAINS.GOERLI),
      },
      target: {
        contractName: "AuthdMockTarget",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol:AuthdMockTarget",
        name: "Compound USDT",
        symbol: "cUSDT",
        decimals: 8,
        address: CUSDT_TOKEN.get(CHAINS.GOERLI),
        adapter: "0xAFe0235D674Be9A63316eAd6e6Cd5E3FA9047b43",
      },
      target4626: {
        contractName: "MockERC4626_Unique",
        contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockERC4626.sol:MockERC4626",
        name: "Morpho-Aave Usdt Stablecoin Supply Vault",
        symbol: "maUSDT",
        decimals: 18,
        address: MORPHO_USDT.get(CHAINS.GOERLI),
      },
    },
  ],
  // TODO: get WETH name of token and change it herrer
  stake: {
    contractName: "AuthdMockToken",
    contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol:AuthdMockToken",
    name: "WETH",
    symbol: "WETH",
    decimals: 18,
    address: WETH_TOKEN.get(CHAINS.GOERLI),
  },
  reward: {
    contractName: "AuthdMockToken",
    contract: "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol:AuthdMockToken",
    name: "Sense Reward Token",
    symbol: "SRT",
    decimals: 18,
    address: REWARD_TOKEN.get(CHAINS.GOERLI),
  },
};

const GOERLI_FACTORIES = [
  {
    address: "0xDbE7deE84f9A32E5b2CA8215ea6Ad85b4c293655",
    contract: "MockCropFactory",
    contractName: "MockCropFactory",
    ifee: ethers.utils.parseEther("0.0010"), // 0.1%
    stake: GOERLI_TOKENS.stake.address,
    stakeSize: ethers.utils.parseEther("0.05"), // 0.05 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 1, // 1 = weekly
    tilt: 0,
    guard: ethers.utils.parseEther("100000"), // $100'000 (not used in Goerli)
    targets: [GOERLI_TOKENS.tokens[0].target, GOERLI_TOKENS.tokens[1].target, GOERLI_TOKENS.tokens[2].target],
    maturities: MATURITIES,
    reward: GOERLI_TOKENS.reward,
  },
  {
    address: "0x27F6f7E23b4D77FE9aD7f9A0756a9b40bddE32c9",
    contract: "Mock4626CropFactory",
    contractName: "Mock4626CropFactory",
    ifee: ethers.utils.parseEther("0.0010"), // 0.1%
    stake: GOERLI_TOKENS.stake.address,
    stakeSize: ethers.utils.parseEther("0.05"), // 0.05 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    mode: 1, // 1 = weekly
    tilt: 0,
    guard: ethers.utils.parseEther("100000"), // $100'000 (not used in Goerli)
    targets: [GOERLI_TOKENS.tokens[1].target4626, GOERLI_TOKENS.tokens[2].target4626],
    maturities: MATURITIES,
    reward: GOERLI_TOKENS.reward,
  },
];

const GOERLI_ADAPTERS = [
  {
    isOwnable: true,
    address: "0x7b6da076144b0a9cf0cddf908f605924d9e0a180",
    contractName: "MockOwnableAdapter",
    ifee: ethers.utils.parseEther("0"), // 0%, no issuance fees
    oracle: ethers.constants.AddressZero,
    stake: WETH_TOKEN.get(CHAINS.GOERLI),
    stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    tilt: 0,
    level: 31,
    mode: 0, // 1 = weekly
    target: GOERLI_TOKENS.tokens[0].target,
    maturities: [],
  },
  {
    isOwnable: true,
    address: "0xA1Dc1E9C1a2a087874634cc7D0395658A741027c",
    contractName: "MockOwnableAdapter",
    ifee: ethers.utils.parseEther("0"), // 0%, no issuance fees
    oracle: ethers.constants.AddressZero,
    stake: WETH_TOKEN.get(CHAINS.GOERLI),
    stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    tilt: 0,
    level: 31,
    mode: 0, // 1 = weekly
    target: GOERLI_TOKENS.tokens[1].target,
    maturities: [],
  },
  {
    isOwnable: true,
    address: "0xa4f9b98c1Bce4b0A9Bbe5dcBf17dc64a55C79477",
    contractName: "MockOwnableAdapter",
    ifee: ethers.utils.parseEther("0"), // 0%, no issuance fees
    oracle: ethers.constants.AddressZero,
    stake: WETH_TOKEN.get(CHAINS.GOERLI),
    stakeSize: ethers.utils.parseEther("0.25"), // 0.25 WETH
    minm: 0, // 0 days
    maxm: (10 * 365.25 * 24 * 60 * 60).toString(), // 10 years
    tilt: 0,
    level: 31,
    mode: 0, // 1 = weekly
    target: GOERLI_TOKENS.tokens[2].target,
    maturities: [],
  },
];

module.exports = {
  5: {
    divider: DIVIDER_1_2_0.get(CHAINS.GOERLI),
    periphery: PERIPHERY_1_4_0.get(CHAINS.GOERLI),
    oracle: "0xB3e70779c1d1f2637483A02f1446b211fe4183Fa",
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.GOERLI),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.GOERLI),
    factories: GOERLI_FACTORIES,
    adapters: GOERLI_ADAPTERS,
    data: GOERLI_TOKENS,
    rlvFactory: RLV_FACTORY.get(CHAINS.GOERLI),
    rollerPeriphery: ROLLER_PERIPHERY.get(CHAINS.GOERLI),
    rollerUtils: ROLLER_UTILS.get(CHAINS.GOERLI),
    balancerVault: BALANCER_VAULT.get(CHAINS.GOERLI),
  },
};
