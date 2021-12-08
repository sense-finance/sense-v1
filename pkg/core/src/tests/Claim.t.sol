// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Token } from "../tokens/Token.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { FixedMath } from "../external/FixedMath.sol";

contract Claims is TestHelper {
    using FixedMath for uint256;

    function testFuzzCollect(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(claim);
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdiv(cscale, FixedMath.WAD);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testFuzzCollectOnTransfer(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(claim), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= bcBalanceBefore.fdiv(cscale, FixedMath.WAD);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectOnTransferFrom(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(claim), address(alice));
        alice.doTransferFrom(address(claim), address(bob), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= bcBalanceBefore.fdiv(cscale, FixedMath.WAD);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }
}
