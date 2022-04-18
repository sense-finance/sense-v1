import Decimal from "decimal.js";
import optimjs from "optimization-js";
import SETTINGS from "./settings.js";

// Assumes a scale of 1 and an issuance fee of 0
class SpaceFluxer {
  constructor(now, ttl, TS, G2, initScale, ifee) {
    this.now = now;
    this.ttl = ttl;
    this.TS = TS;
    this.G2 = G2;
    this.initScale = initScale;
    this.scale = initScale;
    this.ifee = ifee;

    this.ptReserves = new Decimal(0);
    this.targetReserves = new Decimal(0);
    this.supply = new Decimal(0);
  }

  setScale(scale) {
    this.scale = scale;
  }

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

  buyYTs(initialTarget, desiredTargetBack = new Decimal("0")) {
    // Function to optimize, takes normal JS numbers
    return ([targetToBorrow]) => {
      targetToBorrow = new Decimal(targetToBorrow);
      const totalTargetBal = initialTarget.add(targetToBorrow);
      const ptsFromIssuance = totalTargetBal.times(new Decimal("1").minus(this.ifee)).times(this.scale);
      const targetOut = this._swapPTsForTarget(ptsFromIssuance);
      return Math.abs(targetOut.sub(desiredTargetBack).sub(targetToBorrow).toNumber());
    };
  }

  // Swap PTs for target, dont update reserves
  _swapPTsForTarget(amountIn) {
    const ttm = new Decimal(this.ttl - this.now);
    const t = this.TS.times(ttm);
    const a = new Decimal(1).minus(this.G2.times(t));

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
const spaceFluxer = new SpaceFluxer(NOW, MATURITY, TS, G2, INIT_SCALE, IFEE);

// Init space pool reserves
spaceFluxer.mint(new Decimal(targetToJoin));
spaceFluxer.swapPTsForTarget(new Decimal(ptsToSwapIn));

console.log("State:", spaceFluxer);
console.log("\nArgs:", { targetToJoin, ptsToSwapIn, targetInForYTs, optimalTargetReturned });

// Check price
const ptPrice = spaceFluxer.swapPTsForTarget(new Decimal("0.00001")).times(100000);
console.log("\nPT Price:", ptPrice);

// Optimize YT buy
spaceFluxer.setScale(CURRENT_SCALE);
const buyYTTargetToBorrow = spaceFluxer.buyYTs(new Decimal(targetInForYTs), new Decimal(optimalTargetReturned));
console.log("\nOptimal amount to borrow:", optimjs.minimize_Powell(buyYTTargetToBorrow, [0.5]).argument[0]);
