import Decimal from "decimal.js";
import optimjs from "optimization-js";

// Assumes a scale of 1 and an issuance fee of 0
class SpaceFluxer {
  constructor(now, ttl, TS, G2) {
    this.now = now;
    this.ttl = ttl;
    this.TS = TS;
    this.G2 = G2;

    this.ptReserves = new Decimal(0);
    this.targetReserves = new Decimal(0);
    this.supply = new Decimal(0);
  }

  mint(supplyToMint) {
    if (this.supply.eq(0)) {
      this.supply = supplyToMint;
      this.targetReserves = supplyToMint;
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

  buyYTs(initialTarget) {
    // Function to optimize, takes normal JS numbers
    return ([targetToBorrow]) => {
      targetToBorrow = new Decimal(targetToBorrow);
      const totalTargetBal = initialTarget.add(targetToBorrow);
      // Issue
      const ptsFromIssuance = totalTargetBal;
      const targetOut = this._swapPTsForTarget(ptsFromIssuance);
      return Math.abs(targetOut.sub(targetToBorrow).toNumber());
    };
  }

  // Swap PTs for target, dont update reserves
  _swapPTsForTarget(amountIn) {
    const ttm = new Decimal(this.ttl - this.now);
    const t = this.TS.times(ttm);
    const a = new Decimal(1).minus(this.G2.times(t));

    const _ptReserves = new Decimal(this.ptReserves).add(this.supply);
    const _targetReserves = new Decimal(this.targetReserves);
    const x1 = _ptReserves.pow(a);
    const y1 = _targetReserves.pow(a);

    const x2 = _ptReserves.add(amountIn).pow(a);

    const yPost = x1.add(y1).sub(x2).pow(new Decimal(1).div(a));
    const targetOut = _targetReserves.sub(yPost);

    return targetOut;
  }
}

const ONE_YEAR_IN_SECONDS = 31536000;
const TS = new Decimal("1").div(ONE_YEAR_IN_SECONDS * 12);
console.log(ONE_YEAR_IN_SECONDS);
const G2 = new Decimal("1000").div("950");

const spaceFluxer = new SpaceFluxer(0, ONE_YEAR_IN_SECONDS, TS, G2);

spaceFluxer.mint(new Decimal("1"));
spaceFluxer.swapPTsForTarget(new Decimal("0.5"));
console.log(spaceFluxer);

const buyYTTargetToBorrow = spaceFluxer.buyYTs(new Decimal("0.005"));
console.log(optimjs.minimize_Powell(buyYTTargetToBorrow, [0.5]));

console.log(spaceFluxer.swapPTsForTarget(new Decimal("0.0001")).times(10000));
