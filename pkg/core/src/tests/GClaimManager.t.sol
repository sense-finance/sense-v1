// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Claim } from "../tokens/Claim.sol";
import { GClaimManager } from "../modules/GClaimManager.sol";
import { Periphery } from "../Periphery.sol";

import { Hevm } from "./test-helpers/Hevm.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract DividerMock {}

contract GClaimsManager is TestHelper {
    using FixedMath for uint256;
    using FixedMath for uint96;

    /* ========== join() tests ========== */

    function testCantJoinIfInvalidMaturity(uint96 balance) public {
        uint48 maturity = uint48(block.timestamp - 1 days);
        //        uint256 balance = 1e18;
        try alice.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantJoinIfSeriesDoesntExists(uint96 balance) public {
        uint48 maturity = getValidMaturity(2021, 10);
        //        uint256 balance = 10e18;
        try alice.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantJoinIfNotEnoughClaim(uint96 balance) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;
        hevm.warp(block.timestamp + 1 days);
        bob.doApprove(address(claim), address(bob.gClaimManager()));
        try bob.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantJoinIfNotEnoughClaimAllowance(uint96 balance) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, balance);
        uint256 claimBalance = Claim(claim).balanceOf(address(bob));
        try bob.doJoin(address(adapter), maturity, claimBalance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantJoinAfterFirstGClaimNotEnoughTargetBalance() public {
        uint256 tBase = 10**target.decimals();
        divider.setGuard(address(target), 10000000000000000000000 * tBase);

        adapter.setScale(0.1e18); // freeze scale so no excess is generated
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        // bob issues and joins
        uint256 bbalance = target.balanceOf(address(bob));
        bbalance = bbalance - calculateExcess(bbalance, maturity, claim);
        bob.doIssue(address(adapter), maturity, bbalance);
        uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
        bob.doApprove(address(claim), address(bob.gClaimManager()));
        bob.doJoin(address(adapter), maturity, bobClaimBalance);
        uint256 bobGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        assertEq(bobGclaimBalance, bobClaimBalance);

        // alice issues and joins
        adapter.setScale(0); // unfreeze
        uint256 abalance = target.balanceOf(address(alice));
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(adapter), maturity, abalance);
        alice.doApprove(address(claim), address(bob.gClaimManager()));
        hevm.warp(block.timestamp + 20 days);
        uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
        alice.doCollect(address(claim));
        alice.doTransfer(address(target), address(bob), target.balanceOf(address(alice)));

        try alice.doJoin(address(adapter), maturity, aliceClaimBalance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testJoinFirstGClaim(uint96 balance) public {
        // creating new periphery as the one from test helper already had a first gclaim call
        Periphery newPeriphery = new Periphery(
            address(divider),
            address(poolManager),
            address(yieldSpaceFactory),
            address(balancerVault)
        );
        divider.setPeriphery(address(newPeriphery));
        alice.setPeriphery(newPeriphery);
        bob.setPeriphery(newPeriphery);
        periphery = newPeriphery;
        poolManager.setIsTrusted(address(periphery), true);
        alice.doApprove(address(stake), address(periphery));

        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;

        bob.doIssue(address(adapter), maturity, balance);
        bob.doApprove(address(claim), address(bob.gClaimManager()));
        uint256 claimBalance = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(adapter), maturity, claimBalance);
        uint256 gclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        assertEq(gclaimBalance, claimBalance);
    }

    // TODO: re-add this test once we use glcaims again
    // function testJoinAfterFirstGClaim(uint96 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address claim) = sponsorSampleSeries(address(alice), maturity);
    //     uint256 claimBaseUnit = 10**Claim(claim).decimals();

    //     // bob issues and joins
    //     //        uint256 balance = 10 * claimBaseUnit;
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(claim), address(bob.gClaimManager()));
    //     uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobClaimBalance);
    //     uint256 bobGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
    //     assertEq(bobGclaimBalance, bobClaimBalance);

    //     // alice issues and joins
    //     alice.doIssue(address(adapter), maturity, balance);
    //     alice.doApprove(address(claim), address(bob.gClaimManager()));
    //     alice.doApprove(address(target), address(bob.gClaimManager()));
    //     uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
    //     uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceClaimBalance);
    //     uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
    //     uint256 aliceGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(alice));
    //     assertEq(aliceGclaimBalance, aliceClaimBalance);
    //     assertEq(aliceTargetBalAfter, aliceTargetBalBefore);
    // }

    // TODO: re-add this test once we use glcaims again
    // function testJoinAfterFirstGClaimWithdrawsGap(uint96 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address claim) = sponsorSampleSeries(address(alice), maturity);
    //     uint256 claimBaseUnit = 10**Claim(claim).decimals();

    //     // bob issues and joins
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(claim), address(bob.gClaimManager()));
    //     uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobClaimBalance);
    //     uint256 bobGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
    //     assertEq(bobGclaimBalance, bobClaimBalance);

    //     // alice issues and joins
    //     hevm.warp(block.timestamp + 1 days);
    //     adapter.scale();
    //     uint256 balanceMinusExcess = uint96(balance - calculateExcess(balance, maturity, claim));
    //     target.balanceOf(address(alice));
    //     alice.doIssue(address(adapter), maturity, balanceMinusExcess);
    //     alice.doApprove(address(claim), address(alice.gClaimManager()));
    //     alice.doApprove(address(target), address(alice.gClaimManager()));
    //     uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
    //     uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceClaimBalance);
    //     (, uint256 currScale) = adapter._lscale();
    //     uint256 initScale = alice.gClaimManager().inits(address(claim));
    //     uint256 gap = (aliceClaimBalance * currScale) / (currScale - initScale) / 10**18;
    //     uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
    //     uint256 aliceGclaimBalance = ERC20(alice.gClaimManager().gclaims(address(claim))).balanceOf(address(alice));
    //     assertEq(aliceGclaimBalance, aliceClaimBalance);
    //     assertEq(aliceTargetBalAfter + gap, aliceTargetBalBefore);
    // }

    /* ========== exit() tests ========== */

    function testCantExitIfSeriesDoesntExists(uint96 balance) public {
        uint48 maturity = getValidMaturity(2021, 10);
        //        uint256 balance = 1e18;
        try alice.doExit(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testExitFirstGClaim(uint96 balance) public {
        // creating new periphery as the one from test helper already had a first gclaim call
        Periphery newPeriphery = new Periphery(
            address(divider),
            address(poolManager),
            address(yieldSpaceFactory),
            address(balancerVault)
        );
        divider.setPeriphery(address(newPeriphery));
        alice.setPeriphery(newPeriphery);
        bob.setPeriphery(newPeriphery);
        periphery = newPeriphery;
        poolManager.setIsTrusted(address(periphery), true);
        alice.doApprove(address(stake), address(periphery));

        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;

        bob.doIssue(address(adapter), maturity, balance);
        bob.doApprove(address(claim), address(bob.gClaimManager()));
        uint256 claimBalanceBefore = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(adapter), maturity, claimBalanceBefore);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 gclaimBalanceBefore = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        bob.doExit(address(adapter), maturity, gclaimBalanceBefore);
        uint256 gclaimBalanceAfter = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        uint256 claimBalanceAfter = Claim(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        assertEq(gclaimBalanceAfter, 0);
        assertEq(claimBalanceAfter, claimBalanceBefore);
        assertEq(tBalanceBefore, tBalanceAfter);
    }

    function testExitGClaimWithCollected(uint96 balance) public {
        balance = fuzzWithBounds(balance, 1000);
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        // avoid fuzz tests in which nothing is issued
        if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;
        hevm.warp(block.timestamp + 1 days);
        balance = balance - uint96(calculateExcess(balance, maturity, claim));
        bob.doIssue(address(adapter), maturity, balance);
        bob.doApprove(address(claim), address(bob.gClaimManager()));
        hevm.warp(block.timestamp + 1 days);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 claimBalanceBefore = Claim(claim).balanceOf(address(bob));
        bob.doJoin(address(adapter), maturity, claimBalanceBefore);
        hevm.warp(block.timestamp + 3 days);
        uint256 gclaimBalanceBefore = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        bob.doExit(address(adapter), maturity, gclaimBalanceBefore);
        uint256 gclaimBalanceAfter = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
        uint256 claimBalanceAfter = Claim(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        assertEq(gclaimBalanceAfter, 0);
        assertEq(claimBalanceAfter, claimBalanceBefore);
        assertTrue(tBalanceAfter > tBalanceBefore); // TODO: assert exact collected value
    }

    // TODO: re-add this test once we use glcaims again
    // function testExitAfterFirstGClaim(uint96 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address claim) = sponsorSampleSeries(address(alice), maturity);
    //     // avoid fuzz tests in which nothing is issued
    //     if (calculateAmountToIssue(balance, Claim(claim).BASE_UNIT()) == 0) return;

    //     // bob issues and joins
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(claim), address(bob.gClaimManager()));
    //     uint256 bobClaimBalance = Claim(claim).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobClaimBalance);
    //     uint256 bobGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(bob));
    //     assertEq(bobGclaimBalance, bobClaimBalance);

    //     // alice issues and joins
    //     hevm.warp(block.timestamp + 1 days);
    //     adapter.scale();
    //     uint256 balanceMinusExcess = uint96(balance - calculateExcess(balance, maturity, claim));
    //     alice.doIssue(address(adapter), maturity, balanceMinusExcess);
    //     alice.doApprove(address(claim), address(bob.gClaimManager()));
    //     alice.doApprove(address(target), address(bob.gClaimManager()));
    //     uint256 aliceClaimBalance = Claim(claim).balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceClaimBalance);
    //     uint256 aliceGclaimBalance = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(alice));
    //     assertEq(aliceGclaimBalance, aliceClaimBalance);

    //     // alice exits
    //     hevm.warp(block.timestamp + 3 days);
    //     uint256 tBalanceBefore = target.balanceOf(address(alice));
    //     alice.doExit(address(adapter), maturity, aliceGclaimBalance);
    //     uint256 gclaimBalanceAfter = ERC20(bob.gClaimManager().gclaims(address(claim))).balanceOf(address(alice));
    //     uint256 claimBalanceAfter = Claim(claim).balanceOf(address(alice));
    //     uint256 tBalanceAfter = target.balanceOf(address(alice));
    //     assertEq(gclaimBalanceAfter, 0);
    //     assertEq(claimBalanceAfter, aliceClaimBalance);
    //     assertTrue(tBalanceAfter > tBalanceBefore);
    // }
}