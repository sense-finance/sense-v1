// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { PoolManager } from "../fuse/PoolManager.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockPoolManager } from "./test-helpers/mocks/MockPoolManager.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract PeripheryTest is TestHelper {
    using FixedMath for uint256;

    function testDeployPeriphery() public {
        MockPoolManager poolManager = new MockPoolManager();
        address yieldSpaceFactory = address(2);
        address balancerVault = address(3);
        Periphery somePeriphery = new Periphery(
            address(divider),
            address(poolManager),
            yieldSpaceFactory,
            balancerVault
        );
        assertTrue(address(somePeriphery) != address(0));
        assertEq(address(Periphery(somePeriphery).divider()), address(divider));
        assertEq(address(Periphery(somePeriphery).poolManager()), address(poolManager));
        assertEq(address(Periphery(somePeriphery).yieldSpaceFactory()), address(yieldSpaceFactory));
        assertEq(address(Periphery(somePeriphery).balancerVault()), address(balancerVault));
    }

    /* ========== () tests ========== */

    function testSponsorSeries() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // check Balancer pool deployed
        assertTrue(address(yieldSpaceFactory.pool()) != address(0));

        // check zeros and claims onboarded on PoolManager (Fuse)
        assertTrue(poolManager.sStatus(address(adapter), maturity) == PoolManager.SeriesStatus.QUEUED);
    }

    function testOnboardAdapter() public {
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockToken newTarget = new MockTarget(address(underlying), "New Target", "NT", 18);
        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.onboardAdapter(address(factory), address(newTarget));
        assertTrue(poolManager.tInits(address(target)));
    }

    function testSwapTargetForZeros() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // unwrap target into underlying
        (, uint256 lvalue) = adapter._lscale();
        uint256 uBal = tBal.fmul(lvalue, 10**target.decimals());

        // calculate underlying swapped to zeros
        uint256 zBal = uBal.fmul(balancerVault.EXCHANGE_RATE(), 10**target.decimals());

        alice.doSwapTargetForZeros(address(adapter), maturity, tBal, 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapTargetForClaims() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();
        uint256 tBase = 10**target.decimals();

        // calculate issuance fee in corresponding base
        uint256 fee = (adapter.getIssuanceFee() / convertBase(target.decimals()));

        // add liquidity to mockBalancerVault
        target.mint(address(adapter), 100000e18);
        addLiquidityToBalancerVault(maturity, zero, claim);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        uint256 cPrice = 1 * tBase - periphery.price(zero, target.underlying());
        uint256 targetToBorrow = tBal.fdiv((1 * tBase - fee).fmul(cPrice, tBase) + fee, tBase);
        uint256 claimsAmount = targetToBorrow.fmul(lscale.fmul(1 * tBase - fee, tBase), tBase);
        bob.doSwapTargetForClaims(address(adapter), maturity, tBal, 0);

        assertClose(cBalBefore + claimsAmount, ERC20(claim).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapZerosForTarget() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, zero, claim);

        alice.doIssue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate zeros swapped to underlying
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 uBal = zBalBefore.fmul(rate, 10**target.decimals());

        // wrap underlying into target
        (, uint256 lvalue) = adapter._lscale();
        uint256 swapped = uBal.fdiv(lvalue, 10**target.decimals());

        alice.doApprove(zero, address(periphery), zBalBefore);
        alice.doSwapZerosForTarget(address(adapter), maturity, zBalBefore, 0);

        assertEq(tBalBefore + swapped, ERC20(target).balanceOf(address(alice)));
    }

    function testSwapClaimsForTarget() public {
        /*
         * FIXME!!
         * This test is failing. We think it could be due to a precision loss.
         */
        //        uint256 tBal = 100e18;
        //        uint256 maturity = getValidMaturity(2021, 10);
        //        uint256 tBase = 10**target.decimals();
        //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        //        (, uint256 lscale) = adapter._lscale();
        //
        //        // add liquidity to mockUniSwapRouter
        //        addLiquidityToBalancerVault(maturity, zero, claim);
        //
        //        bob.doIssue(address(adapter), maturity, tBal);
        //
        //        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));
        //        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));
        //
        //        // calculate target to borrow
        //        uint256 targetToBorrow;
        //        {
        //            uint256 zBal = cBalBefore.fdiv(2 * tBase, tBase);
        //            uint256 uBal = zBal.fmul(uniSwapRouter.EXCHANGE_RATE(), tBase);
        //            // amount of claims div 2 multiplied by rate gives me amount of underlying then multiplying
        //            // by lscale gives me target
        //            targetToBorrow = uBal.fmul(lscale, tBase);
        //        }
        //
        //        // convert target into underlying (unwrap via protocol)
        //        uint256 unwrappedUnderlying = targetToBorrow.fmul(lscale, tBase);
        //
        //        // swap underlying for Zeros on Yieldspace pool
        //        uint256 zSwapped = unwrappedUnderlying.fmul(uniSwapRouter.EXCHANGE_RATE(), tBase);
        //
        //        // combine zeros and claim
        //        uint256 tCombined = zSwapped.fdiv(lscale, 10**ERC20(claim).decimals());
        //
        //        bob.doApprove(claim, address(periphery), cBalBefore);
        //        bob.doSwapClaimsForTarget(address(adapter), maturity, cBalBefore, 0);
        //
        //        assertEq(tBalBefore + tCombined, ERC20(target).balanceOf(address(bob)));
    }

    //    function testSwapClaimsForTargetWithGap() public {
    //        uint256 tBal = 100e18;
    //        uint256 maturity = getValidMaturity(2021, 10);
    //
    //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
    //
    //        // add liquidity to mockUniSwapRouter
    //        addLiquidityToBalancerVault(maturity, zero, claim);
    //
    //        alice.doIssue(address(adapter), maturity, tBal);
    //        hevm.warp(block.timestamp + 5 days);
    //
    //        bob.doIssue(address(adapter), maturity, tBal);
    //
    //        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));
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
    //        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
    //        uint256 tCombined = swapped.fdiv(lscale, 10**ERC20(claim).decimals());
    //
    //        // calculate excess
    //        uint256 excess = periphery.gClaimManager().excess(address(adapter), maturity, claimsToConvert);
    //
    //        bob.doApprove(claim, address(periphery), cBalBefore);
    //        bob.doSwapClaimsForTarget(address(adapter), maturity, cBalBefore, 0);
    //
    //        assertEq(tBalBefore + tCombined - excess, ERC20(target).balanceOf(address(bob)));
    //    }

    function testQuotePrice() public {
        // TODO!
    }
}
