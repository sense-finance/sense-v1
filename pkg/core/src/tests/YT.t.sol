// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { Token } from "../tokens/Token.sol";
import { YT } from "../tokens/YT.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Divider } from "../Divider.sol";
import { Periphery } from "../Periphery.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

contract Yield is TestHelper {
    using FixedMath for uint256;

    function testFuzzCollect(uint128 tBal) public {
        tBal = uint128(bound(tBal, MIN_TARGET, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        vm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);
        vm.prank(bob);
        uint256 collected = YT(yt).collect();
        uint256 ytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(cscale);
        assertEq(ytBalanceBefore, ytBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectOnTransfer(uint128 tBal) public {
        tBal = uint128(bound(tBal, MIN_TARGET, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        vm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);
        vm.prank(bob);
        Token(yt).transfer(alice, bytBalanceBefore);

        uint256 aytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = bytBalanceBefore.fdiv(lscale);
        collect -= bytBalanceBefore.fdivUp(cscale);
        assertEq(aytBalanceBefore + bytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectOnTransferFrom(uint128 tBal) public {
        tBal = uint128(bound(tBal, MIN_TARGET, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        vm.warp(block.timestamp + 1 days);

        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);
        vm.prank(bob);
        ERC20(yt).approve(alice, type(uint256).max);
        Token(yt).transferFrom(bob, alice, bytBalanceBefore);
        uint256 aytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = bytBalanceBefore.fdiv(lscale);
        collect -= bytBalanceBefore.fdivUp(cscale);
        assertEq(aytBalanceBefore + bytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceAfter, 0);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testEmptyTransferFromDoesNotCollect() public {
        uint256 tBal = 10 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        vm.warp(block.timestamp + 10 days);

        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);
        vm.prank(bob);
        ERC20(yt).approve(alice, type(uint256).max);
        Token(yt).transferFrom(bob, alice, 0);
        uint256 aytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 bytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);
        uint256 collected = tBalanceAfter - tBalanceBefore;
        assertEq(aytBalanceBefore, aytBalanceAfter);
        assertEq(bytBalanceBefore, bytBalanceAfter);
        assertEq(collected, 0);
    }
}
