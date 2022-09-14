// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { Levels } from "@sense-finance/v1-utils/src/libs/Levels.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockAdapter, MockCropAdapter, MockBaseAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { Divider } from "../Divider.sol";
import { Token } from "../tokens/Token.sol";
import { YT } from "../tokens/YT.sol";

contract Dividers is TestHelper {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;
    using FixedMath for uint128;
    using FixedMath for uint64;
    using Errors for string;

    address[] public usrs;
    uint256[] public lscales;

    /* ========== initSeries() tests ========== */

    function testCantInitSeriesNotEnoughStakeBalance() public {
        uint256 balance = stake.balanceOf(alice);
        stake.transfer(bob, balance - STAKE_SIZE / 2);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesNotEnoughStakeAllowance() public {
        ERC20(address(stake)).safeApprove(address(periphery), 0);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesAdapterNotEnabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        divider.setAdapter(address(adapter), false);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesIfAlreadyExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.expectRevert(abi.encodeWithSelector(Errors.DuplicateSeries.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesActiveSeriesReached() public {
        uint256 SERIES_TO_INIT = 3;
        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
            uint256 nextMonthDate = DateTimeFull.addMonths(block.timestamp, i);
            nextMonthDate = getValidMaturity(DateTimeFull.getYear(nextMonthDate), DateTimeFull.getMonth(nextMonthDate));
            (address pt, address yt) = periphery.sponsorSeries(address(adapter), nextMonthDate, true);
            increaseScale(address(target));
            assertTrue(address(pt) != address(0));
            assertTrue(address(yt) != address(0));
        }
        uint256 lastDate = DateTimeFull.addMonths(block.timestamp, SERIES_TO_INIT + 1);
        lastDate = getValidMaturity(DateTimeFull.getYear(lastDate), DateTimeFull.getMonth(lastDate));
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), lastDate, true);
    }

    function testCantInitSeriesWithMaturityBeforeTimestamp() public {
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 8, 1, 0, 0, 0);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesLessThanMinMaturity() public {
        hevm.warp(1631923200);
        // 18-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesMoreThanMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2022, 1, 1, 0, 0, 0);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesIfModeInvalid() public {
        DEFAULT_ADAPTER_PARAMS.mode = 4;
        MockCropAdapter adapter = MockCropAdapter(
            deployMockAdapter(address(divider), address(target), address(reward))
        );

        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Tuesday
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testCantInitSeriesIfNotTopWeek() public {
        DEFAULT_ADAPTER_PARAMS.mode = 1;
        MockCropAdapter adapter = MockCropAdapter(
            deployMockAdapter(address(divider), address(target), address(reward))
        );

        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 5, 0, 0, 0); // Tuesday
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testInitSeriesWeekly() public {
        DEFAULT_ADAPTER_PARAMS.mode = 1;
        MockCropAdapter adapter = MockCropAdapter(
            deployMockAdapter(address(divider), address(target), address(reward))
        );

        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000); // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday

        hevm.expectEmit(true, true, true, false);
        emit SeriesInitialized(address(adapter), maturity, address(0), address(0), address(this), adapter.target());

        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        assertTrue(pt != address(0));
        assertTrue(yt != address(0));
        assertEq(ERC20(pt).name(), "4th Oct 2021 cDAI Sense Principal Token, A2");
        assertEq(ERC20(pt).symbol(), "sP-cDAI:04-10-2021:2");
        assertEq(ERC20(yt).name(), "4th Oct 2021 cDAI Sense Yield Token, A2");
        assertEq(ERC20(yt).symbol(), "sY-cDAI:04-10-2021:2");
    }

    function testCantInitSeriesIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("Pausable: paused");
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testInitSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));
        assertEq(ERC20(pt).name(), "1st Oct 2021 cDAI Sense Principal Token, A1");
        assertEq(ERC20(pt).symbol(), "sP-cDAI:01-10-2021:1");
        assertEq(ERC20(yt).name(), "1st Oct 2021 cDAI Sense Yield Token, A1");
        assertEq(ERC20(yt).symbol(), "sY-cDAI:01-10-2021:1");
    }

    function testInitSeriesWithdrawStake() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(alice);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        assertTrue(address(pt) != address(0));
        assertTrue(address(yt) != address(0));
        uint256 afterBalance = stake.balanceOf(alice);
        assertEq(afterBalance, beforeBalance - STAKE_SIZE);
    }

    function testInitThreeSeries() public {
        uint256 SERIES_TO_INIT = 3;
        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
            uint256 nextMonthDate = DateTimeFull.addMonths(block.timestamp, i);
            nextMonthDate = getValidMaturity(DateTimeFull.getYear(nextMonthDate), DateTimeFull.getMonth(nextMonthDate));
            (address pt, address yt) = periphery.sponsorSeries(address(adapter), nextMonthDate, true);
            increaseScale(address(target));
            assertTrue(address(pt) != address(0));
            assertTrue(address(yt) != address(0));
        }
    }

    function testInitSeriesOnMinMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        periphery.sponsorSeries(address(adapter), maturity, true);
    }

    function testInitSeriesOnMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 12, 1, 0, 0, 0);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
    }

    /* ========== settleSeries() tests ========== */

    function testCantSettleSeriesIfDisabledAdapter() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        divider.setAdapter(address(adapter), false);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesAlreadySettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        hevm.expectRevert(abi.encodeWithSelector(Errors.AlreadySettled.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesIfNotSponsorAndSponsorWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesIfNotSponsorCutoffTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesIfSponsorAndCutoffTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesIfNotSponsorAndSponsorTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW - 1 minutes));
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.settleSeries(address(adapter), maturity);
    }

    function testCantSettleSeriesIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("Pausable: paused");
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);

        hevm.expectEmit(true, true, true, true);
        emit SeriesSettled(address(adapter), maturity, address(this));

        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSponsorWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMinLimit() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.subSeconds(maturity, SPONSOR_WINDOW));
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMaxLimit() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW));
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSettlementWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfNotSponsorAndSettlementWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        hevm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
    }

    function testSettleSeriesStakeIsTransferredIfSponsor() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(alice);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(alice);
        assertEq(beforeBalance, afterBalance);
    }

    function testSettleSeriesStakeIsTransferredIfNotSponsor() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + 1 seconds));
        hevm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(bob);
        assertEq(afterBalance, beforeBalance + STAKE_SIZE);
    }

    function testSettleSeriesWithMockBaseAdapter() public {
        divider.setPermissionless(true);
        MockBaseAdapter aAdapter = new MockBaseAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            ISSUANCE_FEE,
            DEFAULT_ADAPTER_PARAMS
        );
        divider.addAdapter(address(aAdapter));
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(aAdapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(aAdapter), maturity);
    }

    function testFuzzSettleSeriesFeesAreTransferredIfSponsor(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = target.balanceOf(alice);
        periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, tBal);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase);
        uint256 afterBalance = target.balanceOf(alice);
        assertClose(afterBalance, beforeBalance - tBal + fee * 2);
    }

    function testFuzzSettleSeriesFeesAreTransferredIfNotSponsor(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 aliceBeforeBalance = target.balanceOf(alice);
        uint256 bobBeforeBalance = target.balanceOf(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, tBal);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(maturity + SPONSOR_WINDOW + 1);
        hevm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase);
        uint256 aliceAfterBalance = target.balanceOf(alice);
        uint256 bobAfterBalance = target.balanceOf(bob);
        assertClose(aliceAfterBalance, aliceBeforeBalance - tBal);
        assertClose(bobAfterBalance, bobBeforeBalance - tBal + fee * 2);
    }

    /* ========== issue() tests ========== */

    function testCantIssueAdapterDisabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        divider.setAdapter(address(adapter), false);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        divider.issue(address(adapter), maturity, tBal);
    }

    function testCantIssueSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        hevm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        divider.issue(address(adapter), maturity, tBal);
    }

    function testCantIssueNotEnoughBalance() public {
        uint256 aliceBalance = target.balanceOf(alice);
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        divider.setGuard(address(adapter), aliceBalance * 2);
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        divider.issue(address(adapter), maturity, aliceBalance + 1);
    }

    function testCantIssueNotEnoughAllowance() public {
        uint256 aliceBalance = target.balanceOf(alice);
        target.approve(address(divider), 0);
        divider.setGuard(address(adapter), aliceBalance);
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        divider.issue(address(adapter), maturity, aliceBalance);
    }

    function testCantIssueIfSeriesSettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        uint256 amount = target.balanceOf(alice);
        hevm.expectRevert(abi.encodeWithSelector(Errors.IssueOnSettle.selector));
        divider.issue(address(adapter), maturity, amount);
    }

    function testCantIssueIfMoreThanCap() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 targetBalance = target.balanceOf(alice);
        divider.setGuard(address(adapter), targetBalance);
        divider.issue(address(adapter), maturity, targetBalance);
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.GuardCapReached.selector));
        divider.issue(address(adapter), maturity, 1e18);
    }

    function testCantIssueIfIssuanceFeeExceedsCap() public {
        divider.setPermissionless(true);

        ISSUANCE_FEE = 1e18;
        MockAdapter aAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        divider.addAdapter(address(aAdapter));
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(aAdapter), maturity, true);
        uint256 amount = target.balanceOf(alice);
        hevm.expectRevert(abi.encodeWithSelector(Errors.IssuanceFeeCapExceeded.selector));
        divider.issue(address(aAdapter), maturity, amount);
    }

    function testCantIssueSeriesIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("Pausable: paused");
        divider.issue(address(adapter), maturity, 100e18);
    }

    function testIssueLevelRestrictions() public {
        // Restrict issuance, enable all other lifecycle methods
        uint16 level = 0x1 + 0x4 + 0x8 + 0x10;

        DEFAULT_ADAPTER_PARAMS.level = level;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);

        // Should be possible to init series
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.startPrank(bob);
        target.approve(address(adapter), type(uint256).max);

        // Can't issue directly through the divider
        hevm.expectRevert(abi.encodeWithSelector(Errors.IssuanceRestricted.selector));
        divider.issue(address(adapter), maturity, 1e18);

        // Can issue through adapter
        adapter.doIssue(maturity, 1e18);

        // It should still be possible to combine
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(bob));
        hevm.stopPrank();
    }

    function testFuzzIssue(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase); // 1 target
        uint256 tBalanceBefore = target.balanceOf(alice);

        // Formula = newBalance.fmul(scale)
        uint256 mintedAmount = (tBal - fee).fmul(adapter.scale());

        hevm.expectEmit(true, false, false, true);
        emit Issued(address(adapter), maturity, mintedAmount, msg.sender);

        divider.issue(address(adapter), maturity, tBal);

        assertEq(ERC20(pt).balanceOf(alice), mintedAmount);
        assertEq(ERC20(yt).balanceOf(alice), mintedAmount);
        assertEq(target.balanceOf(alice), tBalanceBefore - tBal);
    }

    function testIssueIfMoreThanCapButGuardedDisabled() public {
        uint256 balance = target.balanceOf(alice);
        divider.setGuard(address(adapter), balance - 1);
        divider.setGuarded(false);
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        divider.issue(address(adapter), maturity, guard + 1);
    }

    function testFuzzIssueMultipleTimes(uint128 bal) public {
        // if issuing multiple times with bal = 0, the 2nd issue will fail on _reweightLScale because
        // it will attempt to do a division by 0.
        bal = uint128(fuzzWithBounds(bal, 1000, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        uint256 tBase = 10**target.decimals();
        uint256 tBal = bal.fdiv(4 * tBase, tBase);
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase); // 1 target
        uint256 tBalanceBefore = target.balanceOf(alice);
        divider.issue(address(adapter), maturity, tBal);
        divider.issue(address(adapter), maturity, tBal);
        divider.issue(address(adapter), maturity, tBal);
        divider.issue(address(adapter), maturity, tBal);
        // Formula = newBalance.fmul(scale)
        uint256 mintedAmount = (tBal - fee).fmul(adapter.scale());
        assertEq(ERC20(pt).balanceOf(alice), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(ERC20(yt).balanceOf(alice), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(target.balanceOf(alice), tBalanceBefore - tBal.fmul(4 * tBase, tBase));
    }

    function testIssueReweightScale() public {
        uint256 tBal = 1e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        uint256 lscaleFirst = divider.lscales(address(adapter), maturity, alice);

        hevm.warp(block.timestamp + 7 days);
        uint256 lscaleSecond = divider.lscales(address(adapter), maturity, alice);
        divider.issue(address(adapter), maturity, tBal);
        uint256 scaleAfterThrid = adapter.scale();

        hevm.warp(block.timestamp + 7 days);
        uint256 lscaleThird = divider.lscales(address(adapter), maturity, alice);
        divider.issue(address(adapter), maturity, tBal * 5);
        uint256 lscaleFourth = divider.lscales(address(adapter), maturity, alice);

        assertEq(lscaleFirst, lscaleSecond);

        // Exact mean
        assertEq((lscaleSecond + scaleAfterThrid) / 2, lscaleThird);

        // Weighted
        assertEq((lscaleThird * 2 + adapter.scale() * 5) / 7, lscaleFourth);
    }

    /* ========== combine() tests ========== */

    function testCantCombineAdapterDisabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        divider.setAdapter(address(adapter), false);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        divider.combine(address(adapter), maturity, tBal);
    }

    function testCantCombineSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        hevm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        divider.combine(address(adapter), maturity, tBal);
    }

    function testCantCombineSeriesIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("Pausable: paused");
        divider.combine(address(adapter), maturity, 100e18);
    }

    function testCantCombineIfProperLevelIsntSet() public {
        // Restrict combine, enable all other lifecycle methods
        uint16 level = 0x1 + 0x2 + 0x8 + 0x10;

        DEFAULT_ADAPTER_PARAMS.level = level;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.startPrank(bob);
        divider.issue(address(adapter), maturity, 1e18);

        uint256 bytBal = ERC20(yt).balanceOf(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.CombineRestricted.selector));
        divider.combine(address(adapter), maturity, bytBal);

        // Collect still works
        increaseScale(address(target));
        uint256 collected = YT(yt).collect();
        assertGt(collected, 0);

        // Can combine through adapter
        uint256 balance = ERC20(yt).balanceOf(bob);
        Token(pt).transfer(address(adapter), balance);
        Token(yt).transfer(address(adapter), balance);
        uint256 combined = adapter.doCombine(maturity, balance);
        assertGt(combined, 0);
        hevm.stopPrank();
    }

    function testFuzzCantCombineNotEnoughBalance(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 issued = divider.issue(address(adapter), maturity, tBal);
        hevm.expectRevert(arithmeticError);
        divider.combine(address(adapter), maturity, issued + 1);
    }

    function testFuzzCantCombineNotEnoughAllowance(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 issued = divider.issue(address(adapter), maturity, tBal);
        target.approve(address(periphery), 0);
        hevm.expectRevert(arithmeticError);
        divider.combine(address(adapter), maturity, issued + 1);
    }

    function testFuzzCombine(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 11, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        increaseScale(address(target));
        uint256 tBalanceBefore = target.balanceOf(alice);
        uint256 ptBalanceBefore = ERC20(pt).balanceOf(alice);
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);

        hevm.expectEmit(true, true, true, false);
        emit Combined(address(adapter), maturity, 0, address(this));

        uint256 combined = divider.combine(address(adapter), maturity, ptBalanceBefore);

        uint256 tBalanceAfter = target.balanceOf(alice);
        uint256 ptBalanceAfter = ERC20(pt).balanceOf(alice);
        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        assertEq(ptBalanceAfter, 0);
        assertEq(ytBalanceAfter, 0);
        assertClose((combined).fmul(lscale), ptBalanceBefore); // check includes collected target
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale), ptBalanceBefore);
    }

    function testFuzzCombineAtMaturity(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e4, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        increaseScale(address(target));
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        uint256 tBalanceBefore = target.balanceOf(bob);
        uint256 ptBalanceBefore = ERC20(pt).balanceOf(bob);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        hevm.prank(bob);
        divider.combine(address(adapter), maturity, ptBalanceBefore);
        uint256 tBalanceAfter = target.balanceOf(bob);
        uint256 ptBalanceAfter = ERC20(pt).balanceOf(bob);
        uint256 ytBalanceAfter = ERC20(yt).balanceOf(bob);

        assertEq(ptBalanceAfter, 0);
        assertEq(ytBalanceAfter, 0);
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale), ptBalanceBefore);
    }

    /* ========== redeem() tests ========== */

    function testCanRedeemPrincipal() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, 10**target.decimals());
        hevm.warp(maturity);
        uint256 balance = ERC20(pt).balanceOf(alice);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        increaseScale(address(target));

        hevm.expectEmit(true, true, true, false);
        emit PTRedeemed(address(adapter), maturity, 0);

        uint256 redeemed = divider.redeem(address(adapter), maturity, balance);

        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        // Amount of Principal burned == underlying amount
        assertClose(redeemed.fmul(mscale), balance);
        assertEq(balance, ERC20(pt).balanceOf(alice) + balance);
    }

    function testCanRedeemPrincipalOnDisabledAdapter() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, 10**target.decimals());
        hevm.warp(maturity);
        uint256 balance = ERC20(pt).balanceOf(alice);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        divider.setAdapter(address(adapter), false);

        increaseScale(address(target));
        uint256 redeemed = divider.redeem(address(adapter), maturity, balance);

        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        // Amount of Principal burned == underlying amount
        assertClose(redeemed.fmul(mscale), balance);
        assertEq(balance, ERC20(pt).balanceOf(alice) + balance);
    }

    function testCantRedeemPrincipalSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 balance = 1e18;
        hevm.expectRevert(abi.encodeWithSelector(Errors.NotSettled.selector));
        divider.redeem(address(adapter), maturity, balance);
    }

    function testCantRedeemPrincipalSeriesNotSettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        divider.issue(address(adapter), maturity, tBal);
        increaseScale(address(target));
        uint256 balance = ERC20(pt).balanceOf(alice);
        hevm.expectRevert(abi.encodeWithSelector(Errors.NotSettled.selector));
        divider.redeem(address(adapter), maturity, balance);
    }

    function testCantRedeemPrincipalMoreThanBalance() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        uint256 balance = ERC20(pt).balanceOf(alice) + 1e18;
        hevm.expectRevert(arithmeticError);
        divider.redeem(address(adapter), maturity, balance);
    }

    function testCantRedeemPrincipalIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert("Pausable: paused");
        divider.redeem(address(adapter), maturity, 100e18);
    }

    function testFuzzRedeemPrincipal(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1000, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        increaseScale(address(target));
        uint256 ptBalanceBefore = ERC20(pt).balanceOf(alice);
        uint256 balanceToRedeem = ptBalanceBefore;
        divider.redeem(address(adapter), maturity, balanceToRedeem);
        uint256 ptBalanceAfter = ERC20(pt).balanceOf(alice);

        // Formula: tBal = balance / mscale
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        uint256 redeemed = balanceToRedeem.fdiv(mscale);
        // Amount of Principal burned == underlying amount
        assertClose(redeemed.fmul(mscale), ptBalanceBefore);
        assertEq(ptBalanceBefore, ptBalanceAfter + balanceToRedeem);
    }

    function testRedeemPrincipalBalanceIsZero() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        uint256 tBalanceBefore = target.balanceOf(alice);
        uint256 balance = 0;
        divider.redeem(address(adapter), maturity, balance);
        uint256 tBalanceAfter = target.balanceOf(alice);
        assertEq(tBalanceAfter, tBalanceBefore);
    }

    function testRedeemPrincipalPositiveTiltNegativeScale() public {
        // Reserve 10% of pt for Yield
        uint64 tilt = 0.1e18;
        // The Targeted redemption value Alice will send Bob wants, in Underlying
        uint256 intendedRedemptionValue = 50e18;

        DEFAULT_ADAPTER_PARAMS.tilt = tilt;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        // Sanity check
        assertEq(adapter.tilt(), tilt);

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        uint256 tBal = 100e18;
        divider.issue(address(adapter), maturity, tBal);

        // Transfer Principal that would ideally redeem for 50 Underlying at maturity
        // 50 = pt bal * 1 - tilt
        Token(pt).transfer(bob, intendedRedemptionValue.fdiv(1e18 - tilt, 1e18));

        uint256 tBalanceBeforeRedeem = target.balanceOf(bob);
        uint256 principalBalanceBefore = ERC20(pt).balanceOf(bob);
        hevm.warp(maturity);
        // Set scale to 90% of its initial value
        !is4626Target
            ? adapter.setScale(0.9e18)
            : underlying.burn(address(target), (target.totalSupply()).fmul(0.1e18, 1e18));

        divider.settleSeries(address(adapter), maturity);

        hevm.prank(bob);
        uint256 redeemed = divider.redeem(address(adapter), maturity, principalBalanceBefore);

        // Even though the scale has gone down, Principal should redeem for 100% of their intended redemption
        assertClose(redeemed, intendedRedemptionValue.fdiv(adapter.scale(), 1e18), 10);

        uint256 tBalanceAfterRedeem = target.balanceOf(bob);
        // Redeemed amount should match the amount of Target bob got back
        assertEq(tBalanceAfterRedeem - tBalanceBeforeRedeem, redeemed);

        // Bob should have gained Target comensurate with the entire intended Principal redemption value
        assertClose(
            tBalanceBeforeRedeem + intendedRedemptionValue.fdiv(adapter.scale(), 1e18),
            tBalanceAfterRedeem,
            10
        );
    }

    function testRedeemPrincipalNoTiltNegativeScale() public {
        // Sanity check
        assertEq(adapter.tilt(), 0);
        // The Targeted redemption value Alice will send Bob wants, in Underlying
        uint256 intendedRedemptionValue = 50e18;

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        uint256 tBal = 100e18;
        divider.issue(address(adapter), maturity, tBal);

        // Alice transfers Principal that would ideally redeem for 50 Underlying at maturity
        // 50 = pt bal * 1 - tilt
        Token(pt).transfer(bob, intendedRedemptionValue.fdiv(1e18 - adapter.tilt(), 1e18));

        uint256 tBalanceBeforeRedeem = target.balanceOf(bob);
        uint256 principalBalanceBefore = ERC20(pt).balanceOf(bob);
        hevm.warp(maturity);

        // Set scale to 90% of its initial value
        !is4626Target
            ? adapter.setScale(0.9e18)
            : underlying.burn(address(target), (target.totalSupply()).fmul(0.1e18, 1e18));

        divider.settleSeries(address(adapter), maturity);
        hevm.prank(bob);
        uint256 redeemed = divider.redeem(address(adapter), maturity, principalBalanceBefore);

        // Without any Yield pt to cut into, Principal holders should be down to 90% of their intended redemption
        assertClose(redeemed, intendedRedemptionValue.fdiv(adapter.scale(), 1e18).fmul(0.9e18, 1e18), 10);

        uint256 tBalanceAfterRedeem = target.balanceOf(bob);
        // Redeemed amount should match the amount of Target bob got back
        assertEq(tBalanceAfterRedeem - tBalanceBeforeRedeem, redeemed);

        // Bob should have gained Target comensurate with the 90% of his intended Principal redemption value
        assertClose(
            tBalanceBeforeRedeem + intendedRedemptionValue.fdiv(adapter.scale(), 1e18).fmul(0.9e18, 1e18),
            tBalanceAfterRedeem,
            10
        );
    }

    function testRedeenPrincipalHookIsntCalledIfProperLevelIsntSet() public {
        // Enable all Divider lifecycle methods, but not the adapter pt redeem hook
        uint16 level = 0x1 + 0x2 + 0x4 + 0x8 + 0x10;

        DEFAULT_ADAPTER_PARAMS.level = level;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 1e18);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        uint256 btBal = ERC20(pt).balanceOf(bob);
        hevm.prank(bob);
        divider.redeem(address(adapter), maturity, btBal);

        assertEq(adapter.onRedeemCalls(), 0);
    }

    function testRedeenPrincipalHookIsCalledIfProperLevelIsntSet() public {
        uint16 level = 0x1 + 0x2 + 0x4 + 0x8 + 0x10 + 0x20;

        DEFAULT_ADAPTER_PARAMS.level = level;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 1e18);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        uint256 btBal = ERC20(pt).balanceOf(bob);
        hevm.prank(bob);
        divider.redeem(address(adapter), maturity, btBal);
        assertEq(adapter.onRedeemCalls(), 1);
    }

    /* ========== redeemYT() tests ========== */

    function testRedeemYieldPositiveTiltPositiveScale() public {
        // Reserve 10% of pt for Yield
        uint64 tilt = 0.1e18;

        DEFAULT_ADAPTER_PARAMS.tilt = tilt;
        MockCropAdapter adapter = MockCropAdapter(
            deployMockAdapter(address(divider), address(target), address(reward))
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        uint256 maturity = getValidMaturity(2021, 10);
        hevm.prank(bob);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // Can collect normally
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, 100e18);
        increaseScale(address(target));

        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalanceBefore = target.balanceOf(alice);
        uint256 collected = YT(yt).collect();
        assertTrue(adapter.tBalance(alice) > 0);

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 tBalanceAfter = target.balanceOf(alice);
        (, , , , , , , uint256 mscale, uint256 maxscale) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = ytBalanceBefore.fdiv(lscale) - ytBalanceBefore.fdivUp(cscale);
        assertEq(ytBalanceBefore, ytBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);

        hevm.warp(maturity);
        hevm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        collected = YT(yt).collect();
        assertEq(ERC20(yt).balanceOf(alice), 0);
        (, , , , , , , mscale, maxscale) = divider.series(address(adapter), maturity);
        uint256 redeemed = (ytBalanceAfter * FixedMath.WAD) /
            maxscale -
            (ytBalanceAfter * (FixedMath.WAD - tilt)) /
            mscale;
        assertEq(target.balanceOf(alice), tBalanceAfter + collected + redeemed);
        assertClose(adapter.tBalance(alice), 0);

        collected = YT(yt).collect(); // try collecting after redemption
        assertEq(collected, 0);
    }

    function testRedeemYieldPositiveTiltNegativeScale() public {
        // Reserve 10% of pt for Yield
        uint64 tilt = 0.1e18;
        DEFAULT_ADAPTER_PARAMS.tilt = tilt;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        // Sanity check
        assertEq(adapter.tilt(), 0.1e18);

        // Reserve 10% of pt for Yield
        // Sanity check
        assertEq(adapter.scale(), 1e18);

        uint256 maturity = getValidMaturity(2021, 10);
        hevm.prank(bob);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        uint256 tBal = 100e18;
        divider.issue(address(adapter), maturity, tBal);
        assertTrue(adapter.tBalance(alice) > 0);

        uint256 tBalanceBefore = target.balanceOf(alice);
        hevm.warp(maturity);
        !is4626Target
            ? adapter.setScale(0.9e18)
            : underlying.burn(address(target), (target.totalSupply()).fmul(0.1e18, 1e18));

        hevm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        uint256 collected = YT(yt).collect();
        // Nothing to collect if scale went down
        assertEq(collected, 0);
        // Yield tokens should be burned
        assertEq(ERC20(yt).balanceOf(alice), 0);
        uint256 tBalanceAfter = target.balanceOf(alice);
        // Yield holders are cut out completely and don't get any of their pt back
        assertEq(tBalanceBefore, tBalanceAfter);
        assertEq(adapter.tBalance(alice), 0);

        collected = YT(yt).collect(); // try collecting after redemption
        assertEq(collected, 0);
    }

    /* ========== collect() tests ========== */

    function testCanCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 initScale = adapter.scale();
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, 1e18);

        increaseScale(address(target));

        // Scale has grown so there should be excess yt available
        assertTrue(initScale < adapter.scale());

        uint256 collected = YT(yt).collect();
        // Collect succeeds
        assertGt(collected, 0);
    }

    function testCanCollectDisabledAdapterIfSettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 initScale = adapter.scale();
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, 1e18);
        increaseScale(address(target));

        assertTrue(initScale < adapter.scale());

        divider.setAdapter(address(adapter), false);

        // Collect fails if the Series has not been settled
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        YT(yt).collect();

        hevm.warp(maturity + divider.SPONSOR_WINDOW() + divider.SETTLEMENT_WINDOW() + 1);
        divider.backfillScale(address(adapter), maturity, (initScale * 1.2e18) / 1e18, usrs, lscales);

        // Collect succeeds if the Series has been backfilled
        uint256 collected = YT(yt).collect();
        assertGt(collected, 0);
    }

    function testCantCollectIfProperLevelIsntSet() public {
        // Disable collection, enable all other lifecycle methods
        uint16 level = 0x1 + 0x2 + 0x4 + 0x10;
        DEFAULT_ADAPTER_PARAMS.level = level;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 initScale = adapter.scale();

        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, 1e18);
        increaseScale(address(target));

        // Scale has grown so there should be excess yt available
        assertTrue(initScale < adapter.scale());

        // Yet none is collected
        uint256 collected = YT(yt).collect();
        assertEq(collected, 0);

        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        // But it can be collected at maturity
        collected = YT(yt).collect();
        assertGt(collected, 0);

        // It should still be possible to combine
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
    }

    function testFuzzCantCollectIfMaturityAndNotSettled(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(maturity + divider.SPONSOR_WINDOW() + 1);
        hevm.expectRevert(abi.encodeWithSelector(Errors.CollectNotSettled.selector));
        YT(yt).collect();
    }

    function testFuzzCantCollectIfPaused(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(maturity + divider.SPONSOR_WINDOW() + 1);
        divider.setPaused(true);
        hevm.expectRevert("Pausable: paused");
        YT(yt).collect();
    }

    function testCantCollectIfNotYieldContract() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OnlyYT.selector));
        divider.collect(alice, address(adapter), maturity, tBal, alice);
    }

    function testFuzzCollectSmallTBal(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.warp(block.timestamp + 1 days);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalanceBefore = target.balanceOf(alice);

        uint256 collected = YT(yt).collect();
        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 tBalanceAfter = target.balanceOf(alice);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , , , uint256 maxscale) = divider.series(address(adapter), maturity);
        uint256 tBalNow = ytBalanceBefore.fdivUp(maxscale); // preventive round-up towards the protocol
        uint256 tBalPrev = ytBalanceBefore.fdiv(lscale);
        uint256 collect = tBalPrev > tBalNow ? tBalPrev - tBalNow : 0;

        assertEq(ytBalanceBefore, ytBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollect(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);
        increaseScale(address(target));
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalanceBefore = target.balanceOf(alice);

        hevm.expectEmit(true, true, true, false);
        emit Collected(address(adapter), maturity, 0);

        uint256 collected = YT(yt).collect();

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 tBalanceAfter = target.balanceOf(alice);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(cscale);
        assertEq(ytBalanceBefore, ytBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    function testFuzzCollectReward(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1000, type(uint32).max));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, tBal);
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalanceBefore = target.balanceOf(alice);
        uint256 rBalanceBefore = reward.balanceOf(alice);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop);
        uint256 collected = YT(yt).collect();

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 tBalanceAfter = target.balanceOf(alice);
        uint256 rBalanceAfter = reward.balanceOf(alice);

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdiv(cscale);

        assertEq(ytBalanceBefore, ytBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
        assertClose(rBalanceAfter, rBalanceBefore + airdrop);
    }

    function testFuzzCollectRewardMultipleUsers(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1000, type(uint32).max));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        address[3] memory users = [alice, bob, jim];

        divider.issue(address(adapter), maturity, tBal);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        hevm.prank(jim);
        divider.issue(address(adapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop * users.length); // trigger an airdrop

        for (uint256 i = 0; i < users.length; i++) {
            uint256 lscale = divider.lscales(address(adapter), maturity, address(users[i]));
            uint256 ytBalanceBefore = ERC20(yt).balanceOf(address(users[i]));
            uint256 tBalanceBefore = target.balanceOf(address(users[i]));
            uint256 rBalanceBefore = reward.balanceOf(address(users[i]));

            hevm.prank(users[i]);
            uint256 collected = YT(yt).collect();

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 collect;
            {
                (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
                uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
                collect = ytBalanceBefore.fdiv(lscale);
                collect -= ytBalanceBefore.fdiv(cscale);
            }
            assertEq(ytBalanceBefore, ERC20(yt).balanceOf(address(users[i])));
            assertEq(collected, collect);
            assertEq(target.balanceOf(address(users[i])), tBalanceBefore + collected);
            assertClose(reward.balanceOf(address(users[i])), rBalanceBefore + airdrop);
        }
    }

    function testCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1000, type(uint32).max));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop);
        YT(yt).collect();
        assertTrue(adapter.tBalance(alice) > 0);

        reward.mint(address(adapter), airdrop);

        increaseScale(address(target));
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        YT(yt).collect();

        assertEq(adapter.tBalance(alice), 0);
        uint256 collected = YT(yt).collect(); // try collecting after redemption
        assertEq(collected, 0);
    }

    function testFuzzCollectAtMaturityBurnYieldAndDoesNotCallBurnTwice(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        increaseScale(address(target));
        hevm.warp(maturity);
        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);

        divider.settleSeries(address(adapter), maturity);

        hevm.expectEmit(true, true, true, false);
        emit YTRedeemed(address(adapter), maturity, 0);

        hevm.prank(bob);
        uint256 collected = YT(yt).collect();

        // since YTs are burnt, tBalance should be 0
        if (tBal > 0) assertClose(adapter.tBalance(bob), 0); // TODO: why was it > 0? must be 0 (or close to 0 because of rounding), right?

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();

        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(cscale);
        assertEq(collected, collect);
        assertEq(ytBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
        assertClose(adapter.tBalance(bob), 0);
    }

    function testFuzzCollectAfterMaturityAfterEmergencyDoesNotReplaceBackfilled(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        divider.issue(address(adapter), maturity, tBal);
        divider.setAdapter(address(adapter), false); // emergency stop
        uint256 newScale = 20e17;
        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 days);

        hevm.expectEmit(true, false, false, true);
        emit Backfilled(address(adapter), maturity, newScale, usrs, lscales);

        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales); // fix invalid scale value
        divider.setAdapter(address(adapter), true); // re-enable adapter after emergency

        YT(yt).collect();
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        // TODO: check .scale() is not called (like to add the lscale). We can't?
    }

    function testFuzzCollectBeforeMaturityAndSettled(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(maturity - SPONSOR_WINDOW);
        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalanceBefore = target.balanceOf(bob);
        uint256 lvalue = adapter.scale();

        divider.settleSeries(address(adapter), maturity);
        increaseScale(address(target));

        hevm.prank(bob);
        uint256 collected = YT(yt).collect();

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(bob);
        uint256 tBalanceAfter = target.balanceOf(bob);
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        // Formula: collect = tBal / lscale - tBal / scale
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(lvalue);
        assertEq(collected, collect);
        assertEq(ytBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    // test transferring yields to user calls collect()
    function testFuzzCollectTransferAndCollect(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);

        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);

        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 blscale = divider.lscales(address(adapter), maturity, bob);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 btBalanceBefore = target.balanceOf(bob);

        hevm.prank(bob);
        Token(yt).transfer(alice, bytBalanceBefore); // collects and transfer

        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();

        // bob
        uint256 btBalanceAfter = target.balanceOf(bob);
        uint256 bcollected = btBalanceAfter - btBalanceBefore;

        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 bcollect = bytBalanceBefore.fdiv(blscale);
        bcollect -= bytBalanceBefore.fdivUp(cscale);

        assertEq(ERC20(yt).balanceOf(bob), 0);
        assertEq(btBalanceAfter, btBalanceBefore + bcollected);
        assertEq(ERC20(yt).balanceOf(alice), aytBalanceBefore + bytBalanceBefore);
    }

    // test transferring yields to a user calls collect()
    // it also checks that receiver receives corresp. target collected from the yields he already had
    function testFuzzCollectTransferAndCollectWithReceiverHoldingYT(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e10, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        divider.issue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);

        // alice
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 atBalanceBefore = target.balanceOf(alice);

        // bob
        uint256 blscale = divider.lscales(address(adapter), maturity, bob);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 btBalanceBefore = target.balanceOf(bob);

        hevm.prank(bob);
        Token(yt).transfer(alice, bytBalanceBefore); // collects and transfer

        uint256 alscale = divider.lscales(address(adapter), maturity, alice);
        YT(yt).collect();

        uint256 cscale;
        {
            (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
            cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        }

        {
            // alice
            uint256 atBalanceAfter = target.balanceOf(alice);
            uint256 acollected = atBalanceAfter - atBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 acollect = (aytBalanceBefore + bytBalanceBefore).fdiv(alscale);
            acollect -= (aytBalanceBefore + bytBalanceBefore).fdivUp(cscale);
            assertEq(acollected, acollect);
            assertEq(atBalanceAfter, atBalanceBefore + acollected);
            assertEq(ERC20(yt).balanceOf(alice), aytBalanceBefore + bytBalanceBefore);
        }

        {
            // bob
            uint256 btBalanceAfter = target.balanceOf(bob);
            uint256 bcollected = btBalanceAfter - btBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 bcollect = bytBalanceBefore.fdiv(blscale);
            bcollect -= bytBalanceBefore.fdivUp(cscale);

            assertEq(bcollected, bcollect);
            assertEq(btBalanceAfter, btBalanceBefore + bcollected);
            assertEq(ERC20(yt).balanceOf(bob), 0);
        }
    }

    function testFuzzCollectTransferLessThanBalanceAndCollectWithReceiverHoldingYT(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        divider.issue(address(adapter), maturity, tBal);
        increaseScale(address(target));

        // alice
        uint256 aytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 atBalanceBefore = target.balanceOf(alice);

        // bob
        uint256 blscale = divider.lscales(address(adapter), maturity, bob);
        uint256 bytBalanceBefore = ERC20(yt).balanceOf(bob);
        uint256 btBalanceBefore = target.balanceOf(bob);

        hevm.prank(bob);
        uint256 transferValue = tBal / 2;
        Token(yt).transfer(alice, transferValue); // collects and transfer

        uint256 alscale = divider.lscales(address(adapter), maturity, alice);
        YT(yt).collect();

        uint256 cscale;
        {
            (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
            uint256 lvalue = adapter.scale();
            cscale = block.timestamp >= maturity ? mscale : lvalue;
        }

        {
            // alice
            uint256 atBalanceAfter = target.balanceOf(alice);
            uint256 acollected = atBalanceAfter - atBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 acollect = (aytBalanceBefore + transferValue).fdiv(alscale);
            acollect -= (aytBalanceBefore + transferValue).fdivUp(cscale);

            assertEq(acollected, acollect);
            assertEq(atBalanceAfter, atBalanceBefore + acollected);
            assertEq(ERC20(yt).balanceOf(alice), aytBalanceBefore + transferValue);
        }

        {
            // bob
            uint256 btBalanceAfter = target.balanceOf(bob);
            uint256 bcollected = btBalanceAfter - btBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 bcollect = bytBalanceBefore.fdiv(blscale);
            bcollect -= bytBalanceBefore.fdivUp(cscale);

            assertEq(bcollected, bcollect);
            assertEq(ERC20(yt).balanceOf(bob), bytBalanceBefore - transferValue);
            assertEq(btBalanceAfter, btBalanceBefore + bcollected);
        }
    }

    function testFuzzCollectTransferToMyselfAndCollect(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1e12, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        increaseScale(address(target));
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(block.timestamp + 15 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        uint256 ytBalanceBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalanceBefore = target.balanceOf(alice);

        Token(yt).transfer(alice, ytBalanceBefore); // collects and transfer to self

        uint256 ytBalanceAfter = ERC20(yt).balanceOf(alice);
        uint256 tBalanceAfter = target.balanceOf(alice);
        uint256 collected = tBalanceAfter - tBalanceBefore;

        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 cscale = block.timestamp >= maturity ? mscale : adapter.scale();
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = ytBalanceBefore.fdiv(lscale);
        collect -= ytBalanceBefore.fdivUp(cscale);
        assertEq(collected, collect);
        assertEq(ytBalanceAfter, ytBalanceBefore);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    /* ========== backfillScale() tests ========== */

    function testCantBackfillScaleSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        hevm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        divider.backfillScale(address(adapter), maturity, tBal, usrs, lscales);
    }

    function testCantBackfillScaleBeforeCutoffAndAdapterEnabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        (, , , , , , uint256 iscale, uint256 mscale, ) = divider.series(address(adapter), maturity);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.backfillScale(address(adapter), maturity, iscale + 1, usrs, lscales);
    }

    function testCantBackfillScaleSeriesNotGov() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 tBase = 10**target.decimals();
        hevm.prank(bob);
        hevm.expectRevert("UNTRUSTED");
        divider.backfillScale(address(adapter), maturity, 100 * tBase, usrs, lscales);
    }

    function testCantBackfillScaleBeforeCutoffAndAdapterDisabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(maturity);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 1.5e18;
        hevm.expectRevert(abi.encodeWithSelector(Errors.OutOfWindowBoundaries.selector));
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
    }

    function testBackfillScale() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));

        uint256 newScale = 1.1e18;
        usrs.push(alice);
        usrs.push(bob);
        lscales.push(5e17);
        lscales.push(4e17);

        hevm.expectEmit(true, false, false, true);
        emit Backfilled(address(adapter), maturity, newScale, usrs, lscales);

        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);

        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 lscale = divider.lscales(address(adapter), maturity, alice);
        assertEq(lscale, lscales[0]);
        lscale = divider.lscales(address(adapter), maturity, bob);
        assertEq(lscale, lscales[1]);
    }

    function testBackfillScaleDoesNotTransferRewardsIfAlreadyTransferred() public {
        // add some target and stake into adapter
        hevm.prank(alice);
        target.transfer(address(adapter), 100e18);
        stake.mint(address(adapter), 100e18);

        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);
        divider.issue(address(adapter), maturity, 10e18);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 newScale = 1.1e18;
        usrs.push(alice);
        usrs.push(bob);
        lscales.push(5e17);
        lscales.push(4e17);
        uint256 cupTargetBalanceBefore = target.balanceOf(alice);
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        uint256 cupTargetBalanceAfter = target.balanceOf(alice);
        assertEq(cupTargetBalanceBefore, cupTargetBalanceAfter - 0.5e18);
    }

    // @notice if backfill happens while adapter is NOT disabled it is because the current timestamp is > cutoff so stakecoin stake and fees are to the Sense's cup multisig address
    function testFuzzBackfillScaleAfterCutoffAdapterEnabledTransfersStakeAmountAndFees(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 cupTargetBalanceBefore = target.balanceOf(alice);
        uint256 cupStakeBalanceBefore = stake.balanceOf(alice);
        uint256 sponsorTargetBalanceBefore = target.balanceOf(bob);
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(bob);
        hevm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        uint256 tDecimals = target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, tDecimals).fmul(tBal, 10**tDecimals); // 1 target
        hevm.prank(jim);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);

        assertEq(mscale, newScale);
        assertEq(target.balanceOf(bob), sponsorTargetBalanceBefore);
        assertEq(stake.balanceOf(bob), sponsorStakeBalanceBefore - STAKE_SIZE);
        assertEq(target.balanceOf(alice), cupTargetBalanceBefore + fee);
        assertEq(stake.balanceOf(alice), cupStakeBalanceBefore + STAKE_SIZE);
    }

    // @notice if backfill happens while adapter is disabled stakecoin stake is transferred to Sponsor and fees are to the Sense's cup multisig address
    // no matter that the current timestamp is > cutoff
    function testFuzzBackfillScaleAfterCutoffAdapterDisabledTransfersStakeAmountAndFees(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 cupTargetBalanceBefore = target.balanceOf(alice);
        uint256 cupStakeBalanceBefore = stake.balanceOf(alice);
        uint256 sponsorTargetBalanceBefore = target.balanceOf(bob);
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(bob);
        hevm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));
        uint256 tDecimals = target.decimals();
        uint256 tBase = 10**tDecimals;
        uint256 fee = convertToBase(ISSUANCE_FEE, tDecimals).fmul(tBal, tBase); // 1 target
        hevm.prank(jim);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        assertClose(target.balanceOf(alice), cupTargetBalanceBefore + fee);
        assertClose(stake.balanceOf(alice), cupStakeBalanceBefore);
        assertClose(target.balanceOf(bob), sponsorTargetBalanceBefore);
        assertClose(stake.balanceOf(bob), sponsorStakeBalanceBefore);
    }

    // @notice if backfill happens while adapter is disabled, stake is transferred to Sponsor and fees are sent to the Sense's cup multisig address
    function testFuzzBackfillScaleAfterSponsorAndSettlementWindowsTransfersStakecoinStakeAndFees(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 cupTargetBalanceBefore = target.balanceOf(alice);
        uint256 cupStakeBalanceBefore = stake.balanceOf(alice);
        uint256 sponsorTargetBalanceBefore = target.balanceOf(bob);
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(bob);
        hevm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        uint256 tDecimals = target.decimals();
        uint256 tBase = 10**tDecimals;
        uint256 fee = convertToBase(ISSUANCE_FEE, tDecimals).fmul(tBal, tBase); // 1 target
        hevm.prank(jim);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 sponsorTargetBalanceAfter = target.balanceOf(bob);
        uint256 sponsorStakeBalanceAfter = stake.balanceOf(bob);
        assertEq(sponsorTargetBalanceAfter, sponsorTargetBalanceBefore);
        assertEq(sponsorStakeBalanceAfter, sponsorStakeBalanceBefore);
        uint256 cupTargetBalanceAfter = target.balanceOf(alice);
        uint256 cupStakeBalanceAfter = stake.balanceOf(alice);
        assertEq(cupTargetBalanceAfter, cupTargetBalanceBefore + fee);
        assertEq(cupStakeBalanceAfter, cupStakeBalanceBefore);
    }

    function testFuzzBackfillOnlyLScale(uint128 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 0, MAX_TARGET));
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 cupTargetBalanceBefore = target.balanceOf(alice);
        uint256 cupStakeBalanceBefore = stake.balanceOf(alice);
        uint256 sponsorTargetBalanceBefore = target.balanceOf(bob);
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(bob);
        hevm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true);
        increaseScale(address(target));

        hevm.prank(jim);
        divider.issue(address(adapter), maturity, tBal);

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        divider.setAdapter(address(adapter), false);

        usrs.push(bob);
        usrs.push(jim);
        lscales.push(5e17);
        lscales.push(4e17);
        divider.backfillScale(address(adapter), maturity, 0, usrs, lscales);

        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        assertEq(mscale, 0);
        assertClose(target.balanceOf(bob), sponsorTargetBalanceBefore);
        assertClose(stake.balanceOf(bob), sponsorStakeBalanceBefore - STAKE_SIZE);
        assertClose(target.balanceOf(alice), cupTargetBalanceBefore);
        assertClose(stake.balanceOf(alice), cupStakeBalanceBefore);

        uint256 lscale = divider.lscales(address(adapter), maturity, bob);
        assertEq(lscale, lscales[0]);
        lscale = divider.lscales(address(adapter), maturity, jim);
        assertEq(lscale, lscales[1]);
    }

    /* ========== setAdapter() tests ========== */

    function testCantSetAdapterIfNotTrusted() public {
        hevm.prank(bob);
        hevm.expectRevert("UNTRUSTED");
        divider.setAdapter(address(adapter), false);
    }

    function testCantSetAdapterWithSameValue() public {
        hevm.expectRevert(abi.encodeWithSelector(Errors.ExistingValue.selector));
        divider.setAdapter(address(adapter), true);
    }

    function testSetAdapterFirst() public {
        // check first adapter added on TestHelper.sol has ID 1
        assertEq(divider.adapterCounter(), 1);
        (uint248 id, , , ) = divider.adapterMeta(address(adapter));
        assertEq(id, 1);
        assertEq(divider.adapterAddresses(1), address(adapter));
    }

    function testSetAdapter() public {
        MockAdapter aAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        uint256 adapterCounter = divider.adapterCounter();

        divider.setAdapter(address(aAdapter), true);
        (uint248 id, bool enabled, , ) = divider.adapterMeta(address(aAdapter));
        assertTrue(enabled);
        assertEq(id, adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));
    }

    function testSetAdapterBackOnKeepsExistingId() public {
        MockAdapter aAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        uint256 adapterCounter = divider.adapterCounter();

        // set adapter on
        divider.setAdapter(address(aAdapter), true);
        (uint248 id, bool enabled, , ) = divider.adapterMeta(address(aAdapter));
        assertTrue(enabled);
        assertEq(id, adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));

        // set adapter off
        divider.setAdapter(address(aAdapter), false);

        // create new adapter
        MockAdapter bAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        divider.setAdapter(address(bAdapter), true);
        (id, enabled, , ) = divider.adapterMeta(address(bAdapter));
        assertTrue(enabled);
        assertEq(id, adapterCounter + 2);
        assertEq(divider.adapterAddresses(adapterCounter + 2), address(bAdapter));

        // set adapter back on
        divider.setAdapter(address(aAdapter), true);
        (id, enabled, , ) = divider.adapterMeta(address(aAdapter));
        assertTrue(enabled);
        assertEq(id, adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));
    }

    /* ========== addAdapter() tests ========== */

    function testCantSetAdapterIfNotAdmin() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        divider.setAdapter(address(0xa), true);
    }

    function testCantAddAdapterWhenNotPermissionless() public {
        divider.setAdapter(address(adapter), false);
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.OnlyPermissionless.selector));
        divider.addAdapter(address(adapter));
    }

    function testCantAddAdapterWithSameValue() public {
        divider.setPermissionless(true);
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.ExistingValue.selector));
        divider.addAdapter(address(adapter));
    }

    function testCantAddAdapterIfPaused() public {
        divider.setPermissionless(true);
        divider.setPaused(true);
        hevm.prank(bob);
        hevm.expectRevert("Pausable: paused");
        divider.addAdapter(address(adapter));
    }

    function testCantReAddAdapter() public {
        divider.setPermissionless(true);
        divider.setAdapter(address(adapter), false);
        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.InvalidAdapter.selector));
        divider.addAdapter(address(adapter));
    }

    function testAddAdapter() public {
        MockAdapter aAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));
        divider.setPermissionless(true);

        hevm.expectEmit(true, true, true, true);
        emit AdapterChanged(address(aAdapter), 2, true);

        hevm.prank(bob);
        divider.addAdapter(address(aAdapter));

        (uint248 id, bool enabled, , ) = divider.adapterMeta(address(adapter));
        assertEq(id, 1);
        assertEq(divider.adapterAddresses(1), address(adapter));
        assertTrue(enabled);
    }

    /* ========== admin actions ========== */

    function testCantSetGuardedIfNotAdmin() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        divider.setGuarded(false);
    }

    function testCanSetGuarded() public {
        assertTrue(divider.guarded());
        hevm.expectEmit(true, true, true, true);
        emit GuardedChanged(false);
        divider.setGuarded(false);
        assertTrue(!divider.guarded());
    }

    function testCantSetGuard() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        divider.setGuard(address(0xa), 100e18);
    }

    function testCanSetGuard() public {
        hevm.expectEmit(true, true, true, true);
        emit GuardChanged(address(0xa), 100e18);
        divider.setGuard(address(0xa), 100e18);
        (, , uint256 guard, ) = divider.adapterMeta(address(0xa));
        assertEq(guard, 100e18);
    }

    function testCantSetPermissionlessIfNotAdmin() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        divider.setPermissionless(true);
    }

    function testCanSetPermissionless() public {
        assertTrue(!divider.permissionless());
        hevm.expectEmit(true, true, true, true);
        emit PermissionlessChanged(true);
        divider.setPermissionless(true);
        assertTrue(divider.permissionless());
    }

    function testCantSetPausedIfNotAdmin() public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        divider.setPaused(true);
    }

    function testCanSetPaused() public {
        assertTrue(!divider.paused());
        divider.setPaused(true);
        assertTrue(divider.paused());
    }

    /* ========== LOGS ========== */

    event Backfilled(
        address indexed adapter,
        uint256 indexed maturity,
        uint256 mscale,
        address[] _usrs,
        uint256[] _lscales
    );
    event GuardChanged(address indexed adapter, uint256 cap);
    event AdapterChanged(address indexed adapter, uint256 indexed id, bool indexed isOn);
    event PeripheryChanged(address indexed periphery);
    event SeriesInitialized(
        address adapter,
        uint256 indexed maturity,
        address pt,
        address yt,
        address indexed sponsor,
        address indexed target
    );
    event Issued(address indexed adapter, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Combined(address indexed adapter, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Collected(address indexed adapter, uint256 indexed maturity, uint256 collected);
    event SeriesSettled(address indexed adapter, uint256 indexed maturity, address indexed settler);
    event PTRedeemed(address indexed adapter, uint256 indexed maturity, uint256 redeemed);
    event YTRedeemed(address indexed adapter, uint256 indexed maturity, uint256 redeemed);
    event GuardedChanged(bool indexed guarded);
    event PermissionlessChanged(bool indexed permissionless);
}
