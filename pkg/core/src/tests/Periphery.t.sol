// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockPoolManager } from "./test-helpers/mocks/MockPoolManager.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract PeripheryTest is TestHelper {
    using FixedMath for uint256;

    uint256 public constant TARGET_TO_BORROW = 10e18;

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

    /* ========== swap tests ========== */

    function testSwapTargetForZeros() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // unwrap target into underlying
        (, uint256 lvalue) = adapter._lscale();
        uint256 uBal = tBal.fmul(lvalue, 10**target.decimals());

        // calculate underlying swapped to zeros
        uint256 zBal = uBal.fdiv(balancerVault.EXCHANGE_RATE(), 10**target.decimals());

        alice.doSwapTargetForZeros(address(adapter), maturity, tBal, 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapUnderlyingForZeros() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lvalue) = adapter._lscale();

        // unwrap target into underlying
        uint256 uBal = tBal.fmul(lvalue, 10**target.decimals());

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate underlying swapped to zeros
        uint256 zBal = uBal.fdiv(balancerVault.EXCHANGE_RATE(), 10**target.decimals());

        alice.doSwapUnderlyingForZeros(address(adapter), maturity, uBal, 0);

        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapTargetForClaims() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();
        uint256 tBase = 10**target.decimals();

        // add liquidity to mockBalancerVault
        target.mint(address(adapter), 100000e18);
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (adapter.getIssuanceFee() / convertBase(target.decimals())).fmul(tBal, tBase);
        uint256 claimsAmount = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        bob.doSwapTargetForClaims(address(adapter), maturity, tBal);

        assertEq(cBalBefore + claimsAmount, ERC20(claim).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapUnderlyingForClaims() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();
        uint256 tBase = 10**target.decimals();

        // unwrap target into underlying
        uint256 uBal = tBal.fmul(lscale, 10**target.decimals());

        // add liquidity to mockBalancerVault
        target.mint(address(adapter), 100000e18);
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (adapter.getIssuanceFee() / convertBase(target.decimals())).fmul(tBal, tBase);
        uint256 claimsAmount = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        bob.doSwapUnderlyingForClaims(address(adapter), maturity, uBal);

        assertEq(cBalBefore + claimsAmount, ERC20(claim).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapZerosForTarget() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

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

    function testSwapZerosForUnderlying() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);

        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        alice.doIssue(address(adapter), maturity, tBal);

        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));

        // calculate zeros swapped to underlying
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 uBal = zBalBefore.fmul(rate, 10**target.decimals());

        alice.doApprove(zero, address(periphery), zBalBefore);
        alice.doSwapZerosForUnderlying(address(adapter), maturity, zBalBefore, 0);

        assertEq(uBalBefore + uBal, ERC20(underlying).balanceOf(address(alice)));
    }

    function testSwapClaimsForTarget() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        bob.doIssue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));

        // swap underlying for Zeros on Yieldspace pool
        uint256 zSwapped = TARGET_TO_BORROW.fdiv(balancerVault.EXCHANGE_RATE(), tBase);

        // combine zeros and claim
        uint256 tCombined = zSwapped.fdiv(lscale, 10**ERC20(claim).decimals());
        uint256 remainingClaimsInTarget = tCombined - TARGET_TO_BORROW;

        bob.doApprove(claim, address(periphery), cBalBefore);
        bob.doSwapClaimsForTarget(address(adapter), maturity, cBalBefore);

        assertEq(tBalBefore + remainingClaimsInTarget, ERC20(target).balanceOf(address(bob)));
    }

    //    function testSwapClaimsForTargetWithGap() public {
    //        uint256 tBal = 100e18;
    //        uint256 maturity = getValidMaturity(2021, 10);
    //
    //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
    //
    //        // add liquidity to mockUniSwapRouter
    //        addLiquidityToBalancerVault(maturity, 1000e18);
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

    /* ========== liquidity tests ========== */
    function testAddLiquidityAndSellClaims() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));

        // calculate target to borrow
        uint256 remainingClaimsInTarget;
        {
            // swap underlying for Zeros on Yieldspace pool
            uint256 zSwapped = TARGET_TO_BORROW.fdiv(balancerVault.EXCHANGE_RATE(), tBase);

            // combine zeros and claim
            uint256 tCombined = zSwapped.fdiv(lscale, 10**ERC20(claim).decimals());
            remainingClaimsInTarget = tCombined - TARGET_TO_BORROW;
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 0);
        uint256 tBalAfter = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(tBalBefore - tBal + remainingClaimsInTarget, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldClaims() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(claim).balanceOf(address(bob));

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            // calculate claims to be issued
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = (balances[1] * tBal) / (balances[1] + balances[0]);
            uint256 fee = convertToBase(adapter.getIssuanceFee(), target.decimals()).fmul(proportionalTarget, tBase);
            toBeIssued = (proportionalTarget - fee).fmul(lscale, Token(zero).BASE_UNIT()); // TODO: sub fee??
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);
        uint256 tBalAfter = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 cBalAfter = ERC20(claim).balanceOf(address(bob));

        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
        assertEq(cBalBefore + toBeIssued, cBalAfter);
    }

    function testRemoveLiquidityBeforeMaturity() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate zeros to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = (balances[1] * tBal) / (balances[1] + balances[0]);
            uint256 fee = convertToBase(adapter.getIssuanceFee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale, Token(zero).BASE_UNIT());

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale, tBase); // underlying amount
            minAmountsOut[1] = toBeIssued; // zeros to be issued
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));

        // calculate liquidity added
        {
            // minAmountsOut to target
            uint256 uBal = minAmountsOut[1].fmul(balancerVault.EXCHANGE_RATE(), 10**target.decimals()); // zero to underlying
            tBal = (minAmountsOut[0] + uBal).fdiv(lscale, tBase); // (zeros (in underlying) + underlying) to target
        }

        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBal);
        bob.doRemoveLiquidityToTarget(address(adapter), maturity, lpBal, minAmountsOut, 0);

        uint256 tBalAfter = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
    }

    function testRemoveLiquidityOnMaturity() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter._lscale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate zeros to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = (balances[1] * tBal) / (balances[1] + balances[0]);
            uint256 fee = convertToBase(adapter.getIssuanceFee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale, Token(zero).BASE_UNIT());

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale, tBase); // underlying amount
            minAmountsOut[1] = toBeIssued; // zeros to be issued
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);

        // settle series
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        (, lscale) = adapter._lscale();

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.getTarget()).balanceOf(address(bob));

        // convert liquidity added to target (which would be the liquidity withdrawn)
        {
            (, , , , , , uint256 mscale, , uint256 tilt) = divider.series(address(adapter), maturity);
            // minAmountsOut to target
            tBal = (minAmountsOut[1] * (FixedMath.WAD - tilt)) / mscale; // redeem zeros (target)
            tBal += minAmountsOut[0].fdiv(lscale, tBase); // zeros redeemed (in target) + underlying to target
        }

        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        (, , , , , , uint256 mscale, uint256 maxscale, uint256 tilt) = divider.series(address(adapter), maturity);

        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBal);
        bob.doRemoveLiquidityToTarget(address(adapter), maturity, lpBal, minAmountsOut, 0);

        uint256 tBalAfter = ERC20(adapter.getTarget()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertClose(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
    }

    function testCantMigrateLiquidityIfTargetsAreDifferent() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        MockTarget otherTarget = new MockTarget(address(underlying), "Compound Usdc", "cUSDC", 8);
        factory.addTarget(address(otherTarget), true);
        address dstAdapter = periphery.onboardAdapter(address(factory), address(otherTarget)); // onboard target through Periphery

        (, , uint256 lpShares) = bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 0);
        uint256[] memory minAmountsOut = new uint256[](2);
        try bob.doMigrateLiquidity(address(adapter), dstAdapter, maturity, maturity, lpShares, minAmountsOut, 0, 0) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TargetsNotMatch);
        }
    }

    function testMigrateLiquidity() public {
        // TODO!
    }

    function testQuotePrice() public {
        // TODO!
    }
}
