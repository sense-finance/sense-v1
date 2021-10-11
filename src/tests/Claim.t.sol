// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Token } from "../tokens/Token.sol";
import { ERC20 } from "solmate/erc20/ERC20.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { FixedMath } from "../external/FixedMath.sol";

contract Claims is TestHelper {
    using FixedMath for uint256;

    function testCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        bob.doIssue(address(feed), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(feed), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(claim);
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale) = divider.series(address(feed), maturity);
        (, uint256 lvalue) = feed.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.wdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.wdiv(cscale, claimBaseUnit);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testCollectOnTransfer() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        bob.doIssue(address(feed), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(feed), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(claim), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale) = divider.series(address(feed), maturity);
        (, uint256 lvalue) = feed.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.wdiv(lscale, claimBaseUnit);
        collect -= bcBalanceBefore.wdiv(cscale, claimBaseUnit);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertTrue(collected > 0);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testCollectOnTransferFrom() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = initSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        bob.doIssue(address(feed), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(feed), maturity, address(bob));
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doApprove(address(claim), address(alice));
        alice.doTransferFrom(address(claim), address(bob), address(alice), bcBalanceBefore);
        uint256 acBalanceAfter = ERC20(claim).balanceOf(address(alice));
        uint256 bcBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale) = divider.series(address(feed), maturity);
        (, uint256 lvalue) = feed.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = bcBalanceBefore.wdiv(lscale, claimBaseUnit);
        collect -= bcBalanceBefore.wdiv(cscale, claimBaseUnit);
        assertEq(acBalanceBefore + bcBalanceBefore, acBalanceAfter);
        assertEq(bcBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertTrue(collected > 0);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }
}
