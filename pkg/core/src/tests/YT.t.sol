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
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(yt);
        uint256 ytBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(cscale);
        assertEq(ytBalanceBefore, ytBalanceAfter);
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
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(yt), address(alice), bytBalanceBefore);
        uint256 aytBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bytBalanceBefore.fdiv(lscale);
        collect -= bytBalanceBefore.fdivUp(cscale);
        assertEq(aytBalanceBefore + bytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceAfter, 0);
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
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(yt), address(alice));
        alice.doTransferFrom(address(yt), address(bob), address(alice), bytBalanceBefore);
        uint256 aytBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bytBalanceBefore.fdiv(lscale);
        collect -= bytBalanceBefore.fdivUp(cscale);
        assertEq(aytBalanceBefore + bytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceAfter, 0);
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

        uint256 aytBalanceBefore = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(yt), address(alice));
        alice.doTransferFrom(address(yt), address(bob), address(alice), 0);
        uint256 aytBalanceAfter = ERC20(yt).balanceOf(address(alice));
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(aytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceBefore, bytBalanceAfter);
        assertEq(collected, 0);
    }
}
