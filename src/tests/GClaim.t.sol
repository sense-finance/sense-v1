// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "solmate/erc20/ERC20.sol";

import { Errors } from "../lib/Errors.sol";
import { Claim } from "../tokens/Claim.sol";
import { GClaim } from "../modules/GClaim.sol";

import { Hevm } from "./test-helpers/Hevm.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract DividerMock {}

contract GClaims is TestHelper {
    /* ========== join() tests ========== */

    function testCantJoinIfInvalidMaturity() public {
        uint256 maturity = block.timestamp - 1 days;
        uint256 balance = 1e18;
        try alice.doJoin(address(feed), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantJoinIfSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 balance = 10e18;
        try alice.doJoin(address(feed), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantJoinIfNotEnoughClaim() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 balance = 10e18;
        hevm.warp(block.timestamp + 1 days);
        bob.doApprove(address(claim), address(gclaim));
        try bob.doJoin(address(feed), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantJoinIfNotEnoughClaimAllowance() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 balance = 10e18;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(feed), maturity, balance);
        uint256 claimBalance = Claim(claim).balanceOf(address(bob));
        try bob.doJoin(address(feed), maturity, claimBalance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantJoinAfterFirstGClaimNotEnoughTargetBalance() public {
        divider.setGuard(address(target), 10000e18 * 10000);

        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);

        // bob issues and joins
        uint256 bbalance = target.balanceOf(address(bob));
        bob.doIssue(address(feed), maturity, bbalance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, bobClaimBalance);
        uint256 bobGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        assertEq(bobGclaimBalance, bobClaimBalance);

        // alice issues and joins
        uint256 abalance = target.balanceOf(address(alice));
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(feed), maturity, abalance);
        alice.doApprove(address(claim), address(gclaim));
        alice.doApprove(address(target), address(gclaim));
        hevm.warp(block.timestamp + 20 days);
        uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
        uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
        alice.doCollect(address(claim));
        alice.doTransfer(address(target), address(bob), target.balanceOf(address(alice)));

        try alice.doJoin(address(feed), maturity, aliceClaimBalance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testJoinFirstGClaim() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 balance = 10e18;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 claimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, claimBalance);
        uint256 gclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        assertEq(gclaimBalance, claimBalance);
    }

    function testJoinAfterFirstGClaim() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);

        // bob issues and joins
        uint256 balance = 10e18;
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, bobClaimBalance);
        uint256 bobGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        assertEq(bobGclaimBalance, bobClaimBalance);

        // alice issues and joins
        alice.doIssue(address(feed), maturity, balance);
        alice.doApprove(address(claim), address(gclaim));
        alice.doApprove(address(target), address(gclaim));
        uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
        uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
        alice.doJoin(address(feed), maturity, aliceClaimBalance);
        uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
        uint256 aliceGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(alice));
        assertEq(aliceGclaimBalance, aliceClaimBalance);
        assertEq(aliceTargetBalAfter, aliceTargetBalBefore);
    }

    function testJoinAfterFirstGClaimWithdrawsGap() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);

        // bob issues and joins
        uint256 balance = 10e18;
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, bobClaimBalance);
        uint256 bobGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        assertEq(bobGclaimBalance, bobClaimBalance);

        // alice issues and joins
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(feed), maturity, balance);
        alice.doApprove(address(claim), address(gclaim));
        alice.doApprove(address(target), address(gclaim));
        uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
        uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
        alice.doJoin(address(feed), maturity, aliceClaimBalance);
        (, uint256 currScale) = feed.lscale();
        uint256 initScale = gclaim.inits(address(claim));
        uint256 gap = (aliceClaimBalance * currScale) / (currScale - initScale) / 10**18;
        uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
        uint256 aliceGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(alice));
        assertEq(aliceGclaimBalance, aliceClaimBalance);
        assertEq(aliceTargetBalAfter + gap, aliceTargetBalBefore);
    }

    /* ========== exit() tests ========== */

    function testCantExitIfSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 balance = 1e18;
        try alice.doExit(address(feed), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testExitFirstGClaim() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 balance = 10e18;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 claimBalanceBefore = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, claimBalanceBefore);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 gclaimBalanceBefore = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        bob.doExit(address(feed), maturity, gclaimBalanceBefore);
        uint256 gclaimBalanceAfter = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        uint256 claimBalanceAfter = Claim(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        assertEq(gclaimBalanceAfter, 0);
        assertEq(claimBalanceAfter, claimBalanceBefore);
        assertEq(tBalanceBefore, tBalanceAfter);
    }

    function testExitGClaimWithCollected() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 balance = 10e18;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 claimBalanceBefore = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, claimBalanceBefore);
        hevm.warp(block.timestamp + 3 days);
        uint256 gclaimBalanceBefore = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        bob.doExit(address(feed), maturity, gclaimBalanceBefore);
        uint256 gclaimBalanceAfter = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        uint256 claimBalanceAfter = Claim(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        assertEq(gclaimBalanceAfter, 0);
        assertEq(claimBalanceAfter, claimBalanceBefore);
        assertTrue(tBalanceAfter > tBalanceBefore); // TODO: assert exact collected value
    }

    function testExitAfterFirstGClaim() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);

        // bob issues and joins
        uint256 balance = 10e18;
        bob.doIssue(address(feed), maturity, balance);
        bob.doApprove(address(claim), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(feed), maturity, bobClaimBalance);
        uint256 bobGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(bob));
        assertEq(bobGclaimBalance, bobClaimBalance);

        // alice issues and joins
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(feed), maturity, balance);
        alice.doApprove(address(claim), address(gclaim));
        alice.doApprove(address(target), address(gclaim));
        hevm.warp(block.timestamp + 1 days);
        uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
        alice.doJoin(address(feed), maturity, aliceClaimBalance);
        uint256 aliceGclaimBalance = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(alice));
        assertEq(aliceGclaimBalance, aliceClaimBalance);

        // alice exits
        hevm.warp(block.timestamp + 3 days);
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        alice.doExit(address(feed), maturity, aliceGclaimBalance);
        uint256 gclaimBalanceAfter = ERC20(gclaim.gclaims(address(claim))).balanceOf(address(alice));
        uint256 claimBalanceAfter = Claim(claim).balanceOf(address(alice));
        uint256 tBalanceAfter = target.balanceOf(address(alice));
        assertEq(gclaimBalanceAfter, 0);
        assertEq(claimBalanceAfter, aliceClaimBalance);
        assertTrue(tBalanceAfter > tBalanceBefore);
    }
}
