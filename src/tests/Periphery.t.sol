// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockPoolManager } from "./test-helpers/mocks/MockPoolManager.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract PeripheryTest is TestHelper {
    using FixedMath for uint256;

    function testDeployPeriphery() public {
        MockPoolManager poolManager = new MockPoolManager();
        address uniFactory = address(2);
        address uniSwapRouter = address(3);
        Periphery somePeriphery = new Periphery(
            address(divider),
            address(poolManager),
            uniFactory,
            uniSwapRouter,
            "Sense Fuse Pool",
            false,
            0,
            0
        );
        assertTrue(address(somePeriphery) != address(0));
        assertEq(address(Periphery(somePeriphery).divider()), address(divider));
        assertEq(address(Periphery(somePeriphery).poolManager()), address(poolManager));
        assertTrue(address(Periphery(somePeriphery).gClaimManager()) != address(0));
        assertEq(address(Periphery(somePeriphery).uniFactory()), address(uniFactory));
        assertEq(address(Periphery(somePeriphery).uniSwapRouter()), address(uniSwapRouter));
    }

    /* ========== () tests ========== */

    function testSponsorSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // check gclaim deployed
        address gclaim = address(periphery.gClaimManager().gclaims(claim));
        assertTrue(gclaim != address(0));

        // check Uniswap pool deployed
        assertTrue(uniFactory.getPool(zero, gclaim, periphery.UNI_POOL_FEE()) != address(0));
        assertTrue(uniFactory.getPool(gclaim, zero, periphery.UNI_POOL_FEE()) != address(0));

        // check zeros and claims onboarded on PoolManager (Fuse)
        //        assertTrue(poolManager.sInits(address(feed), maturity)); // TODO: do when PoolManage ready
    }

    function testOnboardTarget() public {
        // add a new target to the factory supported targets
        MockToken newTarget = new MockToken("New Target", "NT", 18);
        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.onboardTarget(address(feed), 0, address(factory), address(newTarget));
        assertTrue(factory.feeds(address(newTarget)) != address(0));
        // assertTrue(poolManager.tInits(address(target))); // TODO: do when PoolManage ready
    }

    function testSwapTargetForZeros() public {
        uint256 tBal = 100e18;
        uint256 backfill = 1e18; // TODO: calculate this properly
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (divider.ISSUANCE_FEE() / convertBase(target.decimals())).fmul(tBal, 10**target.decimals());

        // calculate zeros to be issued
        (, uint256 lscale) = feed.lscale();
        uint256 issued = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        // calculate gclaims swapped to zeros amount
        zBalBefore += issued + issued.fdiv(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(zero).decimals());

        alice.doSwapTargetForZeros(address(feed), maturity, uint128(tBal), backfill, 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
        // TODO: assert backfill has been withdrawn
    }

    function testSwapTargetForClaims() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (divider.ISSUANCE_FEE() / convertBase(target.decimals())).fmul(tBal, 10**target.decimals());

        // calculate claims to be issued
        (, uint256 lscale) = feed.lscale();
        uint256 issued = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());

        // calculate zeros swapped to claims
        cBalBefore += issued + (issued.fdiv(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(claim).decimals()));

        bob.doSwapTargetForClaims(address(feed), maturity, uint128(tBal), 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapZerosForTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        alice.doIssue(address(feed), maturity, tBal);

        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate zeros to be sold for gclaims
        address gclaim = address(periphery.gClaimManager().gclaims(claim));
        uint256 rate = periphery.price(zero, gclaim, uint128(zBalBefore));
        uint256 zerosToSell = zBalBefore.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(zero).decimals());

        // calculate zeros swapped to gclaims
        uint256 swapped = zerosToSell.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(zero).decimals());

        // calculate target to receive after combining
        uint256 cscale = feed.scale();
        uint256 tCombined = swapped.fdiv(cscale, 10**ERC20(target).decimals());

        alice.doApprove(zero, address(periphery), zBalBefore);
        alice.doSwapZerosForTarget(address(feed), maturity, uint128(zBalBefore), 0);

        assertEq(tBalBefore + tCombined, ERC20(target).balanceOf(address(alice)));
    }

    function testSwapClaimsForTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        bob.doIssue(address(feed), maturity, tBal);

        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));

        // calculate claims to be converted to gclaims
        address gclaim = address(periphery.gClaimManager().gclaims(claim));
        uint256 rate = periphery.price(zero, gclaim, uint128(cBalBefore));
        uint256 claimsToConvert = cBalBefore.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(claim).decimals());

        // calculate gclaims swapped to zeros
        uint256 swapped = claimsToConvert.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(zero).decimals());

        // calculate target to receive after combining
        uint256 cscale = feed.scale();
        uint256 tCombined = swapped.fdiv(cscale, 10**ERC20(claim).decimals());

        bob.doApprove(claim, address(periphery), cBalBefore);
        bob.doSwapClaimsForTarget(address(feed), maturity, uint128(cBalBefore), 0);

        assertEq(tBalBefore + tCombined, ERC20(target).balanceOf(address(bob)));
    }

    function testSwapClaimsForTargetWithGap() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        alice.doIssue(address(feed), maturity, tBal);
        hevm.warp(block.timestamp + 5 days);

        bob.doIssue(address(feed), maturity, tBal);

        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));

        // calculate claims to be converted to gclaims
        address gclaim = address(periphery.gClaimManager().gclaims(claim));
        uint256 rate = periphery.price(zero, gclaim, uint128(cBalBefore));
        uint256 claimsToConvert = cBalBefore.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(claim).decimals());

        // calculate gclaims swapped to zeros
        uint256 swapped = claimsToConvert.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(zero).decimals());

        // calculate target to receive after combining
        uint256 lscale = divider.lscales(address(feed), maturity, address(bob));
        uint256 tCombined = swapped.fdiv(lscale, 10**ERC20(claim).decimals());

        // calculate excess
        uint256 excess = periphery.gClaimManager().excess(address(feed), maturity, claimsToConvert);

        bob.doApprove(claim, address(periphery), cBalBefore);
        bob.doSwapClaimsForTarget(address(feed), maturity, uint128(cBalBefore), 0);

        assertEq(tBalBefore + tCombined - excess, ERC20(target).balanceOf(address(bob)));
    }

    function testQuotePrice() public {
        // TODO!
    }
}
