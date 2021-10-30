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
        Periphery somePeriphery = new Periphery(address(divider), address(poolManager), uniFactory, uniSwapRouter);
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

        // check Uniswap pool deployed
        assertTrue(uniFactory.getPool(zero, address(underlying), periphery.UNI_POOL_FEE()) != address(0));
        assertTrue(uniFactory.getPool(address(underlying), zero, periphery.UNI_POOL_FEE()) != address(0));

        // check zeros and claims onboarded on PoolManager (Fuse)
        assertTrue(poolManager.sInits(address(feed), maturity));
    }

    function testOnboardFeed() public {
        // add a new target to the factory supported targets
        MockToken newTarget = new MockToken("New Target", "NT", 18);
        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.onboardFeed(address(factory), address(newTarget));
        assertTrue(factory.feeds(address(newTarget)) != address(0));
        assertTrue(poolManager.tInits(address(target)));
    }

    function testSwapTargetForZeros() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // unwrap target into underlying
        (, uint256 lvalue) = feed.lscale();
        uint256 uBal = tBal.fmul(lvalue, 10**target.decimals());

        // calculate underlying swapped to zeros
        uint256 zBal = uBal.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**target.decimals());

        alice.doSwapTargetForZeros(address(feed), maturity, tBal, 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapTargetForClaims() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = feed.lscale();
        uint256 tBase = 10**target.decimals();

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (divider.ISSUANCE_FEEissuanceFee() / convertBase(target.decimals())).fmul(tBal, tBase);

        // calculate claims & zeros to be issued
        uint256 issueBal = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());

        // calculate zeros swapped to underlying
        uint256 uBal = issueBal.fmul(uniSwapRouter.EXCHANGE_RATE(), tBase);

        uint256 targetToBorrow;
        {
            // wrap underlying into target (on protocol)
            uint256 wrappedTarget = uBal.fdiv(lscale, tBase);

            // calculate target to borrow
            uint256 cPrice = 1 * tBase - uniSwapRouter.EXCHANGE_RATE();
            uint256 claimsAmount = uBal.fdiv(cPrice, tBase);
            targetToBorrow = claimsAmount.fdiv(lscale, tBase) - wrappedTarget;
        }

        // calculate issuance fee in corresponding base
        fee = (divider.ISSUANCE_FEE() / convertBase(target.decimals())).fmul(targetToBorrow, tBase);

        // calculate claims to be issued
        cBalBefore += issueBal + (targetToBorrow - fee).fmul(lscale, Token(zero).BASE_UNIT());

        bob.doSwapTargetForClaims(address(feed), maturity, tBal, 0);

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

        // calculate zeros swapped to underlying
        uint256 rate = uniSwapRouter.EXCHANGE_RATE();
        uint256 uBal = zBalBefore.fmul(rate, 10**target.decimals());

        // wrap underlying into target
        (, uint256 lvalue) = feed.lscale();
        uint256 swapped = uBal.fdiv(lvalue, 10**target.decimals());

        alice.doApprove(zero, address(periphery), zBalBefore);
        alice.doSwapZerosForTarget(address(feed), maturity, zBalBefore, 0);

        assertEq(tBalBefore + swapped, ERC20(target).balanceOf(address(alice)));
    }

    function testSwapClaimsForTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = feed.lscale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToUniSwapRouter(maturity, zero, claim);

        bob.doIssue(address(feed), maturity, tBal);

        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));

        // calculate target to borrow
        uint256 targetToBorrow;
        {
            uint256 zBal = cBalBefore.fdiv(2 * tBase, tBase);
            uint256 uBal = zBal.fmul(uniSwapRouter.EXCHANGE_RATE(), tBase);
            // amount of claims div 2 multiplied by rate gives me amount of underlying then multiplying
            // by lscale gives me target
            targetToBorrow = uBal.fmul(lscale, tBase);
        }

        // convert target into underlying (unwrap via protocol)
        uint256 unwrappedUnderlying = targetToBorrow.fmul(lscale, tBase);

        // swap underlying for Zeros on Yieldspace pool
        uint256 zSwapped = unwrappedUnderlying.fmul(uniSwapRouter.EXCHANGE_RATE(), tBase);

        // combine zeros and claim
        uint256 tCombined = zSwapped.fdiv(lscale, 10**ERC20(claim).decimals());

        bob.doApprove(claim, address(periphery), cBalBefore);
        bob.doSwapClaimsForTarget(address(feed), maturity, cBalBefore, 0);

        assertEq(tBalBefore + tCombined, ERC20(target).balanceOf(address(bob)));
    }

    //    function testSwapClaimsForTargetWithGap() public {
    //        uint256 tBal = 100e18;
    //        uint256 maturity = getValidMaturity(2021, 10);
    //
    //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
    //
    //        // add liquidity to mockUniSwapRouter
    //        addLiquidityToUniSwapRouter(maturity, zero, claim);
    //
    //        alice.doIssue(address(feed), maturity, tBal);
    //        hevm.warp(block.timestamp + 5 days);
    //
    //        bob.doIssue(address(feed), maturity, tBal);
    //
    //        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(bob));
    //        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));
    //
    //        // calculate claims to be converted to gclaims
    //        address gclaim = address(periphery.gClaimManager().gclaims(claim));
    //        uint256 rate = periphery.price(zero, gclaim);
    //        uint256 claimsToConvert =
    //          cBalBefore.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(claim).decimals());
    //
    //        // calculate gclaims swapped to zeros
    //        uint256 swapped = claimsToConvert.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(zero).decimals());
    //
    //        // calculate target to receive after combining
    //        uint256 lscale = divider.lscales(address(feed), maturity, address(bob));
    //        uint256 tCombined = swapped.fdiv(lscale, 10**ERC20(claim).decimals());
    //
    //        // calculate excess
    //        uint256 excess = periphery.gClaimManager().excess(address(feed), maturity, claimsToConvert);
    //
    //        bob.doApprove(claim, address(periphery), cBalBefore);
    //        bob.doSwapClaimsForTarget(address(feed), maturity, cBalBefore, 0);
    //
    //        assertEq(tBalBefore + tCombined - excess, ERC20(target).balanceOf(address(bob)));
    //    }

    function testQuotePrice() public {
        // TODO!
    }
}
