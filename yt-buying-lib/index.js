import Decimal from "decimal.js";
import optimjs from "optimization-js";
import SETTINGS from "./settings.js";

export class SpaceFluxer {
  constructor({ ttm, ts, g2, scale, initScale, ifee, ptReserves, targetReserves, supply }) {
    this.ttm = new Decimal(ttm);
    this.ts = new Decimal(ts);
    this.g2 = new Decimal(g2);
    this.scale = new Decimal(scale);
    this.initScale = new Decimal(initScale);
    this.ifee = new Decimal(ifee);
    this.ptReserves = new Decimal(ptReserves);
    this.targetReserves = new Decimal(targetReserves);
    this.supply = new Decimal(supply);
  }

  getTargetToBorrow(initialTarget, optimalTargetReturned = new Decimal("0"), initialVector = [0.5]) {
    const result = optimjs.minimize_Powell(this._getYTBuyer(initialTarget, optimalTargetReturned), initialVector)
      .argument[0];
    return result < 0 ? null : result;
  }

  // Update scale
  setScale(scale) {
    this.scale = scale;
  }

  // Mint new lp shares and add to reserves appropriately
  mint(supplyToMint) {
    if (this.supply.eq(0)) {
      this.supply = supplyToMint;
      this.targetReserves = supplyToMint.div(this.initScale);
    } else {
      this.ptReserves = this.ptReserves.add(supplyToMint.div(this.supply).times(this.ptReserves));
      this.targetReserves = this.targetReserves.add(supplyToMint.div(this.supply).times(this.targetReserves));
      this.supply = this.supply.add(supplyToMint);
    }
  }

  // Swap PTs for target, update reserves
  swapPTsForTarget(amountIn) {
    const targetOut = this._swapPTsForTarget(amountIn);
    this.targetReserves = this.targetReserves.sub(targetOut);
    this.ptReserves = this.ptReserves.add(amountIn);
    return targetOut;
  }

  // Create a function to a YT buy and return the amount of Target remaining at the end
  _getYTBuyer(initialTarget, optimalTargetReturned) {
    const exponent = parseInt(Number.parseFloat(initialTarget).toExponential(0).split("e")[1]);
    // Set multiplier on the minimization function so that we get precise results, even with small target in values
    const multiplier = exponent >= 0 ? 1 : exponent * -1;
    // Function to optimize, takes normal JS numbers
    return ([targetToBorrow]) => {
      targetToBorrow = new Decimal(targetToBorrow);
      const totalTargetBal = initialTarget.add(targetToBorrow);
      const ptsFromIssuance = totalTargetBal.times(new Decimal("1").minus(this.ifee)).times(this.scale);
      const targetOut = this._swapPTsForTarget(ptsFromIssuance);
      if (targetOut.isNaN()) {
        return targetToBorrow.toNumber();
      }
      return Math.abs(targetOut.sub(optimalTargetReturned).sub(targetToBorrow).toNumber()) * 10 ** multiplier;
    };
  }

  // Swap PTs for target, dont update reserves
  _swapPTsForTarget(amountIn) {
    const t = this.ts.times(this.ttm);
    const a = new Decimal(1).minus(this.g2.times(t));

    const _ptReserves = new Decimal(this.ptReserves).add(this.supply);
    const _underlyingReserves = new Decimal(this.targetReserves).times(this.initScale);

    const x1 = _ptReserves.pow(a);
    const y1 = _underlyingReserves.pow(a);
    const x2 = _ptReserves.add(amountIn).pow(a);

    const yPost = x1.add(y1).sub(x2).pow(new Decimal(1).div(a));
    const targetOut = _underlyingReserves.sub(yPost).div(this.scale);
    return targetOut;
  }
}

// Settings
const { NOW, MATURITY, TS, G2, INIT_SCALE, CURRENT_SCALE, IFEE } = SETTINGS;

// Args
const [targetToJoin, ptsToSwapIn, targetInForYTs, _optimalTargetReturned] = process.argv.slice(2);
if ([targetToJoin, ptsToSwapIn, targetInForYTs].includes(undefined)) {
  throw new Error(
    `Missing at least one of the three required positional arguments:

    <targetToJoin> <ptsToSwapIn> <targetInForYTs> <[optional] optimalTargetReturned>
    `,
  );
}
const optimalTargetReturned = _optimalTargetReturned || 0;

// Init fluxer
const spaceFluxer = new SpaceFluxer({
  ttm: MATURITY - NOW,
  ts: TS,
  g2: G2,
  scale: CURRENT_SCALE,
  initScale: INIT_SCALE,
  ifee: IFEE,
  ptReserves: 0,
  targetReserves: 0,
  supply: 0,
});

// Init space pool reserves
spaceFluxer.mint(new Decimal(targetToJoin));
spaceFluxer.swapPTsForTarget(new Decimal(ptsToSwapIn));

console.log("State:", spaceFluxer);
console.log("\nArgs:", { targetToJoin, ptsToSwapIn, targetInForYTs, optimalTargetReturned });

// Check price
const ptPrice = spaceFluxer._swapPTsForTarget(new Decimal("0.00001")).times(100000);
console.log("\nPT Price:", ptPrice);

// Optimize YT buy
console.log(
  "\nOptimal amount to borrow:",
  spaceFluxer.getTargetToBorrow(new Decimal(targetInForYTs), new Decimal(optimalTargetReturned)),
);
