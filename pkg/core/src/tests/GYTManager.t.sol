// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { YT } from "../tokens/YT.sol";
import { GYTManager } from "../modules/GYTManager.sol";
import { Periphery } from "../Periphery.sol";

import { Hevm } from "./test-helpers/Hevm.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract DividerMock {}

contract GYTsManager is TestHelper {
    using FixedMath for uint256;
    using FixedMath for uint128;

    /* ========== join() tests ========== */

    function testFuzzCantJoinIfInvalidMaturity(uint128 balance) public {
        uint256 maturity = block.timestamp - 1 days;
        //        uint256 balance = 1e18;
        try alice.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        }
    }

    function testFuzzCantJoinIfSeriesDoesntExists(uint128 balance) public {
        uint256 maturity = getValidMaturity(2021, 10);
        //        uint256 balance = 10e18;
        try alice.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        }
    }

    function testFuzzCantJoinIfNotEnoughYT(uint128 balance) public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance) == 0) return;
        hevm.warp(block.timestamp + 1 days);
        bob.doApprove(address(yt), address(bob.gYTManager()));
        try bob.doJoin(address(adapter), maturity, balance) {
            fail();
        } catch (bytes memory error) {}
    }

    function testFuzzCantJoinIfNotEnoughYieldAllowance(uint128 balance) public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance) == 0) return;
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, balance);
        uint256 yieldBalance = YT(yt).balanceOf(address(bob));
        try bob.doJoin(address(adapter), maturity, yieldBalance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    function testCantJoinAfterFirstGYTNotEnoughTargetBalance() public {
        adapter.setScale(0.1e18); // freeze scale so no excess is generated
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);

        // bob issues and joins
        uint256 bbalance = target.balanceOf(address(bob));
        bbalance = bbalance - calculateExcess(bbalance, maturity, yt);
        bob.doIssue(address(adapter), maturity, bbalance);
        uint256 bobYieldBalance = YT(yt).balanceOf(address(bob));
        bob.doApprove(address(yt), address(bob.gYTManager()));
        bob.doJoin(address(adapter), maturity, bobYieldBalance);
        uint256 bobGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
        assertEq(bobGyieldBalance, bobYieldBalance);

        // alice issues and joins
        adapter.setScale(0); // unfreeze
        uint256 abalance = target.balanceOf(address(alice));
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(adapter), maturity, abalance);
        alice.doApprove(address(yt), address(bob.gYTManager()));
        hevm.warp(block.timestamp + 20 days);
        uint256 aliceYieldBalance = YT(yt).balanceOf(address(alice));
        alice.doCollect(address(yt));
        alice.doTransfer(address(target), address(bob), target.balanceOf(address(alice)));

        try alice.doJoin(address(adapter), maturity, aliceYieldBalance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    // TODO: re-add this test once we use glcaims again
    // function testFuzzJoinFirstGYT(uint128 balance) public {
    //     // creating new periphery as the one from test helper already had a first gyield call
    //     Periphery newPeriphery = new Periphery(
    //         address(divider),
    //         address(poolManager),
    //         address(spaceFactory),
    //         address(balancerVault)
    //     );
    //     divider.setPeriphery(address(newPeriphery));
    //     alice.setPeriphery(newPeriphery);
    //     bob.setPeriphery(newPeriphery);
    //     periphery = newPeriphery;
    //     poolManager.setIsTrusted(address(periphery), true);
    //     alice.doApprove(address(stake), address(periphery));

    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address yt) = sponsorSampleSeries(address(alice), maturity);
    //     if (calculateAmountToIssue(balance) == 0) return;

    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(yt), address(bob.gYTManager()));
    //     uint256 yieldBalance = YT(yt).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, yieldBalance);
    //     uint256 gyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     assertEq(gyieldBalance, yieldBalance);
    // }

    // TODO: re-add this test once we use glcaims again
    // function testJoinAfterFirstGYT(uint128 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address yt) = sponsorSampleSeries(address(alice), maturity);
    //     uint256 yieldBaseUnit = 10**YT(yt).decimals();

    //     // bob issues and joins
    //     //        uint256 balance = 10 * yieldBaseUnit;
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(yt), address(bob.gYTManager()));
    //     uint256 bobYieldBalance = YT(yt).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobYieldBalance);
    //     uint256 bobGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     assertEq(bobGyieldBalance, bobYieldBalance);

    //     // alice issues and joins
    //     alice.doIssue(address(adapter), maturity, balance);
    //     alice.doApprove(address(yt), address(bob.gYTManager()));
    //     alice.doApprove(address(target), address(bob.gYTManager()));
    //     uint256 aliceYieldBalance = YT(yt).balanceOf(address(alice));
    //     uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceYieldBalance);
    //     uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
    //     uint256 aliceGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(alice));
    //     assertEq(aliceGyieldBalance, aliceYieldBalance);
    //     assertEq(aliceTargetBalAfter, aliceTargetBalBefore);
    // }

    // TODO: re-add this test once we use glcaims again
    // function testJoinAfterFirstGYTWithdrawsGap(uint128 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address yt) = sponsorSampleSeries(address(alice), maturity);
    //     uint256 yieldBaseUnit = 10**YT(yt).decimals();

    //     // bob issues and joins
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(yt), address(bob.gYTManager()));
    //     uint256 bobYieldBalance = YT(yt).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobYieldBalance);
    //     uint256 bobGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     assertEq(bobGyieldBalance, bobYieldBalance);

    //     // alice issues and joins
    //     hevm.warp(block.timestamp + 1 days);
    //     adapter.scale();
    //     uint256 balanceMinusExcess = uint128(balance - calculateExcess(balance, maturity, yt));
    //     target.balanceOf(address(alice));
    //     alice.doIssue(address(adapter), maturity, balanceMinusExcess);
    //     alice.doApprove(address(yt), address(alice.gYTManager()));
    //     alice.doApprove(address(target), address(alice.gYTManager()));
    //     uint256 aliceYieldBalance = YT(yt).balanceOf(address(alice));
    //     uint256 aliceTargetBalBefore = target.balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceYieldBalance);
    //     (, uint256 currScale) = adapter.lscale();
    //     uint256 initScale = alice.gYTManager().inits(address(yt));
    //     uint256 gap = (aliceYieldBalance * currScale) / (currScale - initScale) / 10**18;
    //     uint256 aliceTargetBalAfter = target.balanceOf(address(alice));
    //     uint256 aliceGyieldBalance = ERC20(alice.gYTManager().gyields(address(yt))).balanceOf(address(alice));
    //     assertEq(aliceGyieldBalance, aliceYieldBalance);
    //     assertEq(aliceTargetBalAfter + gap, aliceTargetBalBefore);
    // }

    /* ========== exit() tests ========== */

    function testFuzzCantExitIfSeriesDoesntExists(uint128 balance) public {
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doExit(address(adapter), maturity, balance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        }
    }

    function testFuzzExitFirstGYT(uint128 balance) public {
        balance = 100;
        // creating new periphery as the one from test helper already had a first gyield call
        Periphery newPeriphery = new Periphery(
            address(divider),
            address(poolManager),
            address(spaceFactory),
            address(balancerVault)
        );
        divider.setPeriphery(address(newPeriphery));
        alice.setPeriphery(newPeriphery);
        bob.setPeriphery(newPeriphery);
        periphery = newPeriphery;
        poolManager.setIsTrusted(address(periphery), true);
        alice.doApprove(address(stake), address(periphery));

        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        if (calculateAmountToIssue(balance) == 0) return;

        bob.doIssue(address(adapter), maturity, balance);
        bob.doApprove(address(yt), address(bob.gYTManager()));
        uint256 yieldBalanceBefore = YT(yt).balanceOf(address(bob));
        bob.doJoin(address(adapter), maturity, yieldBalanceBefore);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 gyieldBalanceBefore = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
        bob.doExit(address(adapter), maturity, gyieldBalanceBefore);
        uint256 gyieldBalanceAfter = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
        uint256 yieldBalanceAfter = YT(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        assertEq(gyieldBalanceAfter, 0);
        assertEq(yieldBalanceAfter, yieldBalanceBefore);
        assertEq(tBalanceBefore, tBalanceAfter);
    }

    // TODO: re-add this test once we use glcaims again
    // function testFuzzExitGYTWithCollected(uint128 balance) public {
    //     balance = fuzzWithBounds(balance, 1e12);
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address yt) = sponsorSampleSeries(address(alice), maturity);
    //     // avoid fuzz tests in which nothing is issued
    //     if (calculateAmountToIssue(balance) == 0) return;
    //     hevm.warp(block.timestamp + 1 days);
    //     balance = balance - uint128(calculateExcess(balance, maturity, yt));
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(yt), address(bob.gYTManager()));
    //     hevm.warp(block.timestamp + 1 days);
    //     uint256 tBalanceBefore = target.balanceOf(address(bob));
    //     uint256 yieldBalanceBefore = YT(yt).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, yieldBalanceBefore);
    //     hevm.warp(block.timestamp + 3 days);
    //     uint256 gyieldBalanceBefore = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     bob.doExit(address(adapter), maturity, gyieldBalanceBefore);
    //     uint256 gyieldBalanceAfter = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     uint256 yieldBalanceAfter = YT(yt).balanceOf(address(bob));
    //     uint256 tBalanceAfter = target.balanceOf(address(bob));
    //     assertEq(gyieldBalanceAfter, 0);
    //     assertEq(yieldBalanceAfter, yieldBalanceBefore);
    //     assertTrue(tBalanceAfter > tBalanceBefore); // TODO: assert exact collected value
    // }

    // TODO: re-add this test once we use glcaims again
    // function testExitAfterFirstGYT(uint128 balance) public {
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     (, address yt) = sponsorSampleSeries(address(alice), maturity);
    //     // avoid fuzz tests in which nothing is issued
    //     if (calculateAmountToIssue(balance) == 0) return;

    //     // bob issues and joins
    //     bob.doIssue(address(adapter), maturity, balance);
    //     bob.doApprove(address(yt), address(bob.gYTManager()));
    //     uint256 bobYieldBalance = YT(yt).balanceOf(address(bob));
    //     bob.doJoin(address(adapter), maturity, bobYieldBalance);
    //     uint256 bobGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(bob));
    //     assertEq(bobGyieldBalance, bobYieldBalance);

    //     // alice issues and joins
    //     hevm.warp(block.timestamp + 1 days);
    //     adapter.scale();
    //     uint256 balanceMinusExcess = uint128(balance - calculateExcess(balance, maturity, yt));
    //     alice.doIssue(address(adapter), maturity, balanceMinusExcess);
    //     alice.doApprove(address(yt), address(bob.gYTManager()));
    //     alice.doApprove(address(target), address(bob.gYTManager()));
    //     uint256 aliceYieldBalance = YT(yt).balanceOf(address(alice));
    //     alice.doJoin(address(adapter), maturity, aliceYieldBalance);
    //     uint256 aliceGyieldBalance = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(alice));
    //     assertEq(aliceGyieldBalance, aliceYieldBalance);

    //     // alice exits
    //     hevm.warp(block.timestamp + 3 days);
    //     uint256 tBalanceBefore = target.balanceOf(address(alice));
    //     alice.doExit(address(adapter), maturity, aliceGyieldBalance);
    //     uint256 gyieldBalanceAfter = ERC20(bob.gYTManager().gyields(address(yt))).balanceOf(address(alice));
    //     uint256 yieldBalanceAfter = YT(yt).balanceOf(address(alice));
    //     uint256 tBalanceAfter = target.balanceOf(address(alice));
    //     assertEq(gyieldBalanceAfter, 0);
    //     assertEq(yieldBalanceAfter, aliceYieldBalance);
    //     assertTrue(tBalanceAfter > tBalanceBefore);
    // }
}
