const {
  CHAINS,
  NON_CROP_4626_FACTORY,
  DIVIDER_1_2_0,
  PERIPHERY_1_3_0,
  MORPHO_USDC,
  MORPHO_DAI,
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

const MAINNET_MORPHO_ASSETS = [MORPHO_USDC.get(CHAINS.MAINNET), MORPHO_DAI.get(CHAINS.MAINNET)];

module.exports = {
  // mainnet
  1: {
    divider: DIVIDER_1_2_0.get(CHAINS.MAINNET),
    periphery: PERIPHERY_1_3_0.get(CHAINS.MAINNET),
    erc4626Factory: NON_CROP_4626_FACTORY.get(CHAINS.MAINNET),
    morphoAssets: MAINNET_MORPHO_ASSETS,
  },
};
