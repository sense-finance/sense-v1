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
        //        uint256 tBal = 100e18;
        //        uint256 backfill = 1e18; // TODO: calculate this properly
        //        uint256 maturity = getValidMaturity(2021, 10);
        //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        //
        //        // add liquidity to mockUniSwapRouter
        //        addLiquidityToUniSwapRouter(maturity, zero, claim);
        //
        //        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        //        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));
        //
        //        // calculate issuance fee in corresponding base
        //        uint256 convertBase = 1;
        //        uint256 tDecimals = target.decimals();
        //        if (tDecimals != 18) {
        //            convertBase = tDecimals < 18 ? 10**(18 - tDecimals) : 10**(tDecimals - 18);
        //        }
        //        uint256 fee = (divider.ISSUANCE_FEE() / convertBase).fmul(tBal, 10**target.decimals());
        //
        //        // calculate zeros to be issued
        //        (, uint256 lscale) = feed.lscale();
        //        uint256 issued = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        //
        //        // calculate gclaims swapped to zeros amount
        //        zBalBefore += issued + issued / uniSwapRouter.EXCHANGE_RATE();
        //
        //        alice.doSwapTargetForZeros(address(feed), maturity, tBal, backfill);
        //
        //        assertEq(cBalBefore, ERC20(claim).balanceOf(address(alice)));
        //        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
        //        // TODO: assert backfill has been withdrawn
    }

    function testSwapTargetForClaims() public {
        //        uint256 tBal = 100e18;
        //        uint256 maturity = getValidMaturity(2021, 10);
        //        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        //
        //        // add liquidity to mockUniSwapRouter
        //        addLiquidityToUniSwapRouter(maturity, zero, claim);
        //
        //        uint256 cBalBefore = ERC20(claim).balanceOf(address(alice));
        //        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));
        //
        //        // calculate issuance fee in corresponding base
        //        uint256 convertBase = 1;
        //        uint256 tDecimals = target.decimals();
        //        if (tDecimals != 18) {
        //            convertBase = tDecimals < 18 ? 10**(18 - tDecimals) : 10**(tDecimals - 18);
        //        }
        //        uint256 fee = (divider.ISSUANCE_FEE() / convertBase).fmul(tBal, 10**target.decimals());
        //
        //        // calculate claims to be issued
        //        (, uint256 lscale) = feed.lscale();
        //        uint256 issued = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        //
        //        // calculate zeros swapped to claims
        //        cBalBefore += issued + (issued / uniSwapRouter.EXCHANGE_RATE());
        //
        //        bob.doSwapTargetForClaims(address(feed), maturity, tBal);
        //
        //        assertEq(cBalBefore, ERC20(claim).balanceOf(address(bob)));
        //        assertEq(zBalBefore, ERC20(zero).balanceOf(address(alice)));
    }

    function testSwapZerosForTarget() public {
        //        uint256 tBal = 100e18;
        //        uint256 backfill = 1e18; // TODO: calculate this properly
        //        uint256 maturity = getValidMaturity(2021, 10);
        //
        //        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        //        alice.doIssue(address(feed), maturity, tBal);
        //
        //        uint256 tBalBefore = ERC20(feed.target()).balanceOf(address(alice));
        //        uint256 zBalBefore = ERC20(zero).balanceOf(address(alice));
        //
        //        // calculate zeros to be sold for gclaims
        //        uint256 rate = uniSwapRouter.EXCHANGE_RATE();
        //        uint256 zerosToSell = zBalBefore / (rate + 1);
        //
        //        // calculate zeros swapped to gclaims
        //        uint256 swapped = zerosToSell / uniSwapRouter.EXCHANGE_RATE();
        //
        //        // calculate target to receive after combining
        //        uint256 cscale = feed.scale();
        //        uint256 tBalAfterCombined = (zBalBefore - swapped).fdiv(cscale, 10**ERC20(target).decimals());
        //
        //        alice.doApprove(zero, address(periphery), zBalBefore);
        //        // TODO: how can I stub the price() function?
        //        alice.doSwapZerosForTarget(address(feed), maturity, zBalBefore);
        //        assertEq(tBalBefore + tBalAfterCombined, ERC20(target).balanceOf(address(alice)));
    }

    function testSwapClaimsForTarget() public {
        // TODO!
    }

    function testQuotePrice() public {
        // TODO!
    }
}
