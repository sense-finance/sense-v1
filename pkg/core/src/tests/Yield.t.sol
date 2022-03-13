// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { Token } from "../tokens/Token.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Divider } from "../Divider.sol";

contract Yield is TestHelper {
    using FixedMath for uint256;

    function testFuzzCollect(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(yt);
        uint256 cBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectOnTransfer(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(yt), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= bcBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectOnTransferFrom(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(yt), address(alice));
        alice.doTransferFrom(address(yt), address(bob), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= bcBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testEmptyTransferFromDoesNotCollect() public {
        uint256 tBal = 10e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 10 days);

        uint256 acBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(yt), address(alice));
        alice.doTransferFrom(address(yt), address(bob), address(alice), 0);
        uint256 acBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(acBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceBefore, bcBalanceAfter);
        assertEq(collected, 0);
    }
}