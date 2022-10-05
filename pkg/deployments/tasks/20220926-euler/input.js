const {
  CHAINS,
  SENSE_MULTISIG,
  EULER_USDC,
  NON_CROP_4626_FACTORY,
  DIVIDER_1_2_0,
  PERIPHERY_1_3_0,
} = require("../../hardhat.addresses");
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

// Only for hardhat, we will deploy adapters using Defender
const SAMPLE_MATURITIES = [
  dayjs()
    .utc()
    .month(dayjs().utc().month() + 3)
    .startOf("month")
    .unix(),
  dayjs()
    .utc()
    .month(dayjs().utc().month() + 4)
    .startOf("month")
    .unix(),
];

// TODO: add corresponding markets once we have a decision
const MAINNET_EULER_MARKETS = [EULER_USDC.get(CHAINS.MAINNET)];

module.exports = {
  // mainnet
  1: {
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    periphery: PERIPHERY_1_3_0.get(CHAINS.MAINNET),
    restrictedAdmin: SENSE_MULTISIG.get(CHAINS.MAINNET),
    rewardsRecipient: SENSE_MULTISIG.get(CHAINS.MAINNET),
    markets: MAINNET_EULER_MARKETS,
    series: SAMPLE_MATURITIES,
    factory: NON_CROP_4626_FACTORY.get(CHAINS.MAINNET),
    maxSecondsBeforePriceIsStale: (3 * 24 * 60 * 60).toString(), // 3 days
  },
};
