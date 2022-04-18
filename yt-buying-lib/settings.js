import Decimal from "decimal.js";

const NOW = 0;
const ONE_YEAR_IN_SECONDS = 31536000;
const TS = new Decimal("1").div(ONE_YEAR_IN_SECONDS * 12);
const G2 = new Decimal("1000").div("950");

const INIT_SCALE = new Decimal("1");
const CURRENT_SCALE = new Decimal("1");
const IFEE = new Decimal("0.042");

export default {
  NOW,
  MATURITY: ONE_YEAR_IN_SECONDS,
  TS,
  G2,
  INIT_SCALE,
  CURRENT_SCALE,
  IFEE,
};
