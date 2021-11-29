// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { User } from "./test-helpers/User.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { CropAdapter } from "../adapters/CropAdapter.sol";
import { Divider } from "../Divider.sol";
import { Token } from "../tokens/Token.sol";

contract Dividers is TestHelper {
    using FixedMath for uint256;
    using FixedMath for uint128;
    using Errors for string;

    address[] public usrs;
    uint256[] public lscales;

    /* ========== initSeries() tests ========== */

    function testCantInitSeriesNotEnoughStakeBalance() public {
        uint256 balance = stake.balanceOf(address(alice));
        alice.doTransfer(address(stake), address(bob), balance - convertToBase(STAKE_SIZE, stake.decimals()) / 2);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantInitSeriesNotEnoughStakeAllowance() public {
        alice.doApprove(address(stake), address(periphery), 0);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantInitSeriesAdapterNotEnabled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        divider.setAdapter(address(adapter), false);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantInitSeriesIfAlreadyExists() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.DuplicateSeries);
        }
    }

    function testCantInitSeriesActiveSeriesReached() public {
        uint256 SERIES_TO_INIT = 3;
        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
            uint48 nextMonthDate = uint48(DateTimeFull.addMonths(block.timestamp, i));
            nextMonthDate = getValidMaturity(DateTimeFull.getYear(nextMonthDate), DateTimeFull.getMonth(nextMonthDate));
            (address zero, address claim) = sponsorSampleSeries(address(alice), nextMonthDate);
            hevm.warp(block.timestamp + 1 days);
            assertTrue(address(zero) != address(0));
            assertTrue(address(claim) != address(0));
        }
        uint48 lastDate = uint48(DateTimeFull.addMonths(block.timestamp, SERIES_TO_INIT + 1));
        lastDate = getValidMaturity(DateTimeFull.getYear(lastDate), DateTimeFull.getMonth(lastDate));
        try alice.doSponsorSeries(address(adapter), lastDate) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesWithMaturityBeforeTimestamp() public {
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 8, 1, 0, 0, 0));
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesLessThanMinMaturity() public {
        hevm.warp(1631923200);
        // 18-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0));
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesMoreThanMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesIfModeInvalid() public {
        adapter.setMode(4);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0)); // Tuesday
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesIfNotTopWeek() public {
        adapter.setMode(1);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 5, 0, 0, 0)); // Tuesday
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testInitSeriesWeekly() public {
        adapter.setMode(1);
        hevm.warp(1631664000); // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0)); // Monday
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
        assertEq(ERC20(zero).name(), "Compound Dai 10-2021 Zero #1 by Sense");
        assertEq(ERC20(zero).symbol(), "zcDAI:10-2021:#1");
        assertEq(ERC20(claim).name(), "Compound Dai 10-2021 Claim #1 by Sense");
        assertEq(ERC20(claim).symbol(), "ccDAI:10-2021:#1");
    }

    function testCantInitSeriesIfPaused() public {
        divider.setPaused(true);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testInitSeries() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
        assertEq(ERC20(zero).name(), "Compound Dai 10-2021 Zero #1 by Sense");
        assertEq(ERC20(zero).symbol(), "zcDAI:10-2021:#1");
        assertEq(ERC20(claim).name(), "Compound Dai 10-2021 Claim #1 by Sense");
        assertEq(ERC20(claim).symbol(), "ccDAI:10-2021:#1");
    }

    function testInitSeriesWithdrawStake() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(address(alice));
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        assertTrue(address(zero) != address(0));
        assertTrue(address(claim) != address(0));
        uint256 afterBalance = stake.balanceOf(address(alice));
        assertEq(afterBalance, beforeBalance - convertToBase(STAKE_SIZE, stake.decimals()));
    }

    function testInitThreeSeries() public {
        uint256 SERIES_TO_INIT = 3;
        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
            uint48 nextMonthDate = uint48(DateTimeFull.addMonths(block.timestamp, i));
            nextMonthDate = getValidMaturity(DateTimeFull.getYear(nextMonthDate), DateTimeFull.getMonth(nextMonthDate));
            (address zero, address claim) = sponsorSampleSeries(address(alice), nextMonthDate);
            hevm.warp(block.timestamp + 1 days);
            assertTrue(address(zero) != address(0));
            assertTrue(address(claim) != address(0));
        }
    }

    function testInitSeriesOnMinMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0));
        sponsorSampleSeries(address(alice), maturity);
    }

    function testInitSeriesOnMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 12, 1, 0, 0, 0));
        sponsorSampleSeries(address(alice), maturity);
    }

    /* ========== settleSeries() tests ========== */

    function testCantSettleSeriesIfDisabledAdapter() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        divider.setAdapter(address(adapter), false);
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantSettleSeriesAlreadySettled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.AlreadySettled);
        }
    }

    function testCantSettleSeriesIfNotSponsorAndSponsorWindow() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        try bob.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfNotSponsorCutoffTime() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        try bob.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfSponsorAndCutoffTime() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfNotSponsorAndSponsorTime() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW - 1 minutes));
        try bob.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfPaused() public {
        divider.setPaused(true);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testSettleSeries() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSponsorWindow() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMinLimit() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.subSeconds(maturity, SPONSOR_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMaxLimit() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSettlementWindow() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfNotSponsorAndSettlementWindow() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        bob.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesStakeIsTransferredIfSponsor() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(address(alice));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(address(alice));
        assertEq(beforeBalance, afterBalance);
    }

    function testSettleSeriesStakeIsTransferredIfNotSponsor() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(address(bob));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + 1 seconds));
        bob.doSettleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(address(bob));
        assertEq(afterBalance, beforeBalance + convertToBase(STAKE_SIZE, stake.decimals()));
    }

    function testSettleSeriesFeesAreTransferredIfSponsor(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = target.balanceOf(address(alice));
        sponsorSampleSeries(address(alice), maturity);
        alice.doIssue(address(adapter), maturity, tBal);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase);
        uint256 afterBalance = target.balanceOf(address(alice));
        assertClose(afterBalance, beforeBalance - tBal + fee * 2);
    }

    function testSettleSeriesFeesAreTransferredIfNotSponsor(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 aliceBeforeBalance = target.balanceOf(address(alice));
        uint256 bobBeforeBalance = target.balanceOf(address(bob));
        sponsorSampleSeries(address(alice), maturity);
        alice.doIssue(address(adapter), maturity, tBal);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity + SPONSOR_WINDOW + 1);
        bob.doSettleSeries(address(adapter), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase);
        uint256 aliceAfterBalance = target.balanceOf(address(alice));
        uint256 bobAfterBalance = target.balanceOf(address(bob));
        assertClose(aliceAfterBalance, aliceBeforeBalance - tBal);
        assertClose(bobAfterBalance, bobBeforeBalance - tBal + fee * 2);
    }

    /* ========== issue() tests ========== */

    function testCantIssueAdapterDisabled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        divider.setAdapter(address(adapter), false);
        try alice.doIssue(address(adapter), maturity, tBal) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantIssueSeriesDoesntExists() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try alice.doIssue(address(adapter), maturity, tBal) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantIssueNotEnoughBalance() public {
        uint256 aliceBalance = target.balanceOf(address(alice));
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        divider.setGuard(address(target), aliceBalance * 2);
        try alice.doIssue(address(adapter), maturity, aliceBalance + 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantIssueNotEnoughAllowance() public {
        uint256 aliceBalance = target.balanceOf(address(alice));
        alice.doApprove(address(target), address(divider), 0);
        divider.setGuard(address(target), aliceBalance);
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        bob.doApprove(address(target), address(periphery), 0);
        try alice.doIssue(address(adapter), maturity, aliceBalance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.TransferFromFailed);
        }
    }

    function testCantIssueIfSeriesSettled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 amount = target.balanceOf(address(alice));
        try alice.doIssue(address(adapter), maturity, amount) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.IssueOnSettled);
        }
    }

    function testCantIssueIfMoreThanCap() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 amount = divider.guards(address(target)) + 1;
        try alice.doIssue(address(adapter), maturity, amount) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.GuardCapReached);
        }
    }

    function testCantIssueIfIssuanceFeeExceedsCap() public {
        divider.setPermissionless(true);
        MockAdapter aAdapter = new MockAdapter();
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: address(target),
            stake: address(stake),
            oracle: ORACLE,
            delta: DELTA,
            ifee: 1e18,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });
        aAdapter.initialize(address(divider), adapterParams, address(reward));
        divider.addAdapter(address(aAdapter));
        uint48 maturity = getValidMaturity(2021, 10);
        User(address(alice)).doSponsorSeries(address(aAdapter), maturity);
        uint256 amount = target.balanceOf(address(alice));
        try alice.doIssue(address(aAdapter), maturity, amount) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.IssuanceFeeCapExceeded);
        }
    }

    function testCantIssueSeriesIfPaused() public {
        divider.setPaused(true);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doIssue(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testIssue(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase); // 1 target
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        alice.doIssue(address(adapter), maturity, tBal);
        // Formula = newBalance.fmul(scale)
        (, uint256 lscale) = adapter._lscale();
        uint256 mintedAmount = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        assertEq(ERC20(zero).balanceOf(address(alice)), mintedAmount);
        assertEq(ERC20(claim).balanceOf(address(alice)), mintedAmount);
        assertEq(target.balanceOf(address(alice)), tBalanceBefore - tBal);
    }

    function testIssueIfMoreThanCapButGuardedDisabled() public {
        uint256 aliceBalance = target.balanceOf(address(alice));
        divider.setGuard(address(target), aliceBalance - 1);
        divider.setGuarded(false);
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 amount = divider.guards(address(target)) + 1;
        alice.doIssue(address(adapter), maturity, amount);
    }

    function testIssueMultipleTimes(uint128 bal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = bal.fdiv(4 * tBase, tBase);
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase); // 1 target
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        alice.doIssue(address(adapter), maturity, tBal);
        alice.doIssue(address(adapter), maturity, tBal);
        alice.doIssue(address(adapter), maturity, tBal);
        alice.doIssue(address(adapter), maturity, tBal);
        // Formula = newBalance.fmul(scale)
        (, uint256 lscale) = adapter._lscale();
        uint256 mintedAmount = (tBal - fee).fmul(lscale, Token(zero).BASE_UNIT());
        assertEq(ERC20(zero).balanceOf(address(alice)), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(ERC20(claim).balanceOf(address(alice)), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(target.balanceOf(address(alice)), tBalanceBefore - tBal.fmul(4 * tBase, tBase));
    }

    /* ========== combine() tests ========== */

    function testCantCombineAdapterDisabled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        divider.setAdapter(address(adapter), false);
        try alice.doCombine(address(adapter), maturity, tBal) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantCombineSeriesDoesntExists() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try alice.doCombine(address(adapter), maturity, tBal) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantCombineSeriesIfPaused() public {
        divider.setPaused(true);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doCombine(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testCantCombineNotEnoughBalance(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 issued = bob.doIssue(address(adapter), maturity, tBal);
        try bob.doCombine(address(adapter), maturity, issued + 1) {
            fail();
        } catch (bytes memory error) {
            // Does not return any error message
        }
    }

    function testCantCombineNotEnoughAllowance(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 issued = bob.doIssue(address(adapter), maturity, tBal);
        bob.doApprove(address(target), address(periphery), 0);
        try bob.doCombine(address(adapter), maturity, issued + 1) {
            fail();
        } catch (bytes memory error) {
            // Does not return any error message
        }
    }

    function testCombine(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 zBalanceBefore = ERC20(zero).balanceOf(address(bob));
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        bob.doCombine(address(adapter), maturity, zBalanceBefore);
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 zBalanceAfter = ERC20(zero).balanceOf(address(bob));
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        require(zBalanceAfter == 0);
        require(cBalanceAfter == 0);
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale, Token(zero).BASE_UNIT()), zBalanceBefore);
    }

    function testCombineAtMaturity(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 zBalanceBefore = ERC20(zero).balanceOf(address(bob));

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        bob.doCombine(address(adapter), maturity, zBalanceBefore);
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 zBalanceAfter = ERC20(zero).balanceOf(address(bob));
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));

        require(zBalanceAfter == 0);
        require(cBalanceAfter == 0);
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale, Token(zero).BASE_UNIT()), zBalanceBefore);
    }

    /* ========== redeemZero() tests ========== */
    function testCantRedeemZeroDisabledAdapter() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        divider.setAdapter(address(adapter), false);
        uint256 balance = ERC20(zero).balanceOf(address(alice));
        try alice.doRedeemZero(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantRedeemZeroSeriesDoesntExists() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 balance = 1e18;
        try alice.doRedeemZero(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            // The settled check will fail if the Series does not exist
            assertEq(error, Errors.NotSettled);
        }
    }

    function testCantRedeemZeroSeriesNotSettled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 balance = ERC20(zero).balanceOf(address(bob));
        try bob.doRedeemZero(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSettled);
        }
    }

    function testCantRedeemZeroMoreThanBalance() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 balance = ERC20(zero).balanceOf(address(alice)) + 1e18;
        try alice.doRedeemZero(address(adapter), maturity, balance) {
            fail();
        } catch (bytes memory error) {
            // Does not return any error message
        }
    }

    function testCantRedeemZeroIfPaused() public {
        divider.setPaused(true);
        uint48 maturity = getValidMaturity(2021, 10);
        try alice.doRedeemZero(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testRedeemZero(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000);
        uint48 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 zBalanceBefore = ERC20(zero).balanceOf(address(bob));
        uint256 balanceToRedeem = zBalanceBefore;
        bob.doRedeemZero(address(adapter), maturity, balanceToRedeem);
        uint256 zBalanceAfter = ERC20(zero).balanceOf(address(bob));

        // Formula: tBal = balance / mscale
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        uint256 redeemed = balanceToRedeem.fdiv(mscale, Token(zero).BASE_UNIT());
        // Amount of Zeros burned == underlying amount
        assertClose(redeemed.fmul(mscale, Token(zero).BASE_UNIT()), zBalanceBefore);
        assertEq(zBalanceBefore, zBalanceAfter + balanceToRedeem);
    }

    function testRedeemZeroBalanceIsZero() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        uint256 balance = 0;
        alice.doRedeemZero(address(adapter), maturity, balance);
        uint256 tBalanceAfter = target.balanceOf(address(alice));
        assertEq(tBalanceAfter, tBalanceBefore);
    }

    /* ========== redeemClaim() tests ========== */
    function testRedeemClaimTiltPositiveScale() public {
        // Reserve 10% of principal for Claims
        adapter.setTilt(0.1e18);
        // Sanity check
        assertEq(adapter.tilt(), 0.1e18);

        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        // Can collect normally
        hevm.warp(block.timestamp + 1 days);
        uint256 tBal = 100e18;
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(claim);
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, 10**target.decimals()) -
            cBalanceBefore.fdiv(cscale, 10**target.decimals());
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        collected = bob.doCollect(claim);
        assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        (, , , , , , mscale, , ) = divider.series(address(adapter), maturity);
        uint256 redeemed = cBalanceAfter.fdiv(mscale, 10**target.decimals()).fmul(0.1e18, 10**target.decimals());
        assertEq(target.balanceOf(address(bob)), tBalanceAfter + collected + redeemed);
    }

    function testRedeemClaimNegativeScale() public {
        // Reserve 10% of principal for Claims
        adapter.setTilt(0.1e18);
        // Sanity check
        assertEq(adapter.tilt(), 0.1e18);

        // Reserve 10% of principal for Claims
        adapter.setScale(1e18);
        // Sanity check
        assertEq(adapter.scale(), 1e18);

        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        uint256 tBal = 100e18;
        bob.doIssue(address(adapter), maturity, tBal);

        uint256 tBalanceBefore = ERC20(target).balanceOf(address(bob));
        hevm.warp(maturity);
        adapter.setScale(0.90e18);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 collected = bob.doCollect(claim);
        // Nothing to collect if scale went down
        assertEq(collected, 0);
        // Claim tokens should be burned
        assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        uint256 tBalanceAfter = ERC20(target).balanceOf(address(bob));
        // Claim holders are cut out completely and don't get any of their principal back
        assertEq(tBalanceBefore, tBalanceAfter);
    }

    /* ========== collect() tests ========== */
    function testCantCollectDisabledAdapter() public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        divider.setAdapter(address(adapter), false);
        try alice.doCollect(claim) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantCollectIfMaturityAndNotSettled(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity + divider.SPONSOR_WINDOW() + 1);
        try bob.doCollect(claim) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.CollectNotSettled);
        }
    }

    function testCantCollectIfPaused(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity + divider.SPONSOR_WINDOW() + 1);
        divider.setPaused(true);
        try bob.doCollect(claim) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testCantCollectIfNotClaimContract() public {
        uint256 tBal = 100e18;
        uint48 maturity = getValidMaturity(2021, 10);
        try divider.collect(address(bob), address(adapter), maturity, tBal, address(bob)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OnlyClaim);
        }
    }

    function testCollect(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
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
        uint256 collect = cBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testCollectReward(uint128 tBal) public {
        tBal = fuzzWithBounds(148576927244290395723322121708047222714, 1000, type(uint32).max);
        adapter.setScale(1e18);
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        bob.doIssue(address(adapter), maturity, tBal);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 rBalanceBefore = reward.balanceOf(address(bob));

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop);
        uint256 collected = bob.doCollect(claim);

        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 rBalanceAfter = reward.balanceOf(address(bob));

        // Formula: collect = tBal / lscale - tBal / cscale
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
        assertClose(rBalanceAfter, rBalanceBefore + airdrop);
    }

    function testCollectRewardMultipleUsers(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000, type(uint32).max);
        adapter.setScale(1e18);
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        User[3] memory users = [alice, bob, jim];

        alice.doIssue(address(adapter), maturity, tBal);
        bob.doIssue(address(adapter), maturity, tBal);
        jim.doIssue(address(adapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop * users.length); // trigger an airdrop

        for (uint256 i = 0; i < users.length; i++) {
            uint256 lscale = divider.lscales(address(adapter), maturity, address(users[i]));
            uint256 cBalanceBefore = ERC20(claim).balanceOf(address(users[i]));
            uint256 tBalanceBefore = target.balanceOf(address(users[i]));
            uint256 rBalanceBefore = reward.balanceOf(address(users[i]));

            uint256 collected = users[i].doCollect(claim);

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 collect;
            {
                (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
                (, uint256 lvalue) = adapter._lscale();
                uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
                collect = cBalanceBefore.fdiv(lscale, Token(claim).BASE_UNIT());
                collect -= cBalanceBefore.fdiv(cscale, Token(claim).BASE_UNIT());
            }
            assertEq(cBalanceBefore, ERC20(claim).balanceOf(address(users[i])));
            assertEq(collected, collect);
            assertEq(target.balanceOf(address(users[i])), tBalanceBefore + collected);
            assertClose(reward.balanceOf(address(users[i])), rBalanceBefore + airdrop);
        }
    }

    function testCollectAtMaturityBurnClaimsAndDoesNotCallBurnTwice(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        alice.doSettleSeries(address(adapter), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 collected = bob.doCollect(claim);
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testCollectBeforeMaturityAfterEmergencyDoesNotReplaceBackfilled(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        divider.setAdapter(address(adapter), false); // emergency stop
        uint256 newScale = 20e17;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales); // fix invalid scale value
        divider.setAdapter(address(adapter), true); // re-enable adapter after emergency
        bob.doCollect(claim);
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        // TODO: check .scale() is not called (like to add the lscale). We can't?
    }

    function testCollectBeforeMaturityAndSettled(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity - SPONSOR_WINDOW);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        alice.doSettleSeries(address(adapter), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 collected = bob.doCollect(claim);
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testCollectTransferAndCollect(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 btBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(claim), address(alice), bcBalanceBefore); // collects and transfer
        uint256 btBalanceAfter = target.balanceOf(address(bob));
        uint256 bcollected = btBalanceAfter - btBalanceBefore;
        uint256 acollected = alice.doCollect(claim); // try to collect

        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = bcBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= bcBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(bcollected, collect);
        assertEq(ERC20(claim).balanceOf(address(alice)), bcBalanceBefore);
        assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        assertEq(btBalanceAfter, btBalanceBefore + bcollected);
        assertEq(acollected, 0);
    }

    function testCollectTransferToMyselfAndCollect(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = Token(claim).BASE_UNIT();
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        bob.doTransfer(address(claim), address(bob), cBalanceBefore); // collects and transfer
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 collected = tBalanceAfter - tBalanceBefore;
        uint256 collectedAfterTransfer = alice.doCollect(claim); // try to collect

        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter._lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, claimBaseUnit);
        collect -= cBalanceBefore.fdiv(cscale, claimBaseUnit);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, cBalanceBefore);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
        assertEq(collectedAfterTransfer, 0);
    }

    /* ========== backfillScale() tests ========== */
    function testCantBackfillScaleSeriesDoesntExists() public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try divider.backfillScale(address(adapter), maturity, tBal, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantBackfillScaleBeforeCutoffAndAdapterEnabled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try divider.backfillScale(address(adapter), maturity, tBal, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantBackfillScaleSeriesNotGov() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try alice.doBackfillScale(address(adapter), maturity, tBal, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }

    function testCantBackfillScaleInvalidValue() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 amount = 1 * (10**(target.decimals() - 2));
        try divider.backfillScale(address(adapter), maturity, amount, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }

    function testBackfillScale() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 newScale = 1.1e18;
        usrs.push(address(alice));
        usrs.push(address(bob));
        lscales.push(5e17);
        lscales.push(4e17);
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(alice));
        assertEq(lscale, lscales[0]);
        lscale = divider.lscales(address(adapter), maturity, address(bob));
        assertEq(lscale, lscales[1]);
    }

    function testBackfillScaleBeforeCutoffAndAdapterDisabled() public {
        uint48 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 1.5e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
    }

    // @notice if backfill happens before the maturity and sponsor window, stakecoin stake is transferred to the
    // sponsor and issuance fees are returned to Sense's cup multisig address
    function testBackfillScaleBeforeSponsorWindowTransfersStakeAmountAndFees(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 cupTargetBalanceBefore = target.balanceOf(address(this));
        uint256 cupStakeBalanceBefore = stake.balanceOf(address(this));
        uint256 sponsorTargetBalanceBefore = target.balanceOf(address(alice));
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(address(alice));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 tDecimals = target.decimals();
        uint256 tBase = 10**tDecimals;
        uint256 fee = convertToBase(ISSUANCE_FEE, tDecimals).fmul(tBal, tBase); // 1 target
        bob.doIssue(address(adapter), maturity, tBal);

        hevm.warp(maturity - SPONSOR_WINDOW);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 2 * tBase;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        assertEq(target.balanceOf(address(alice)), sponsorTargetBalanceBefore);
        assertEq(stake.balanceOf(address(alice)), sponsorStakeBalanceBefore);
        assertEq(target.balanceOf(address(this)), cupTargetBalanceBefore + fee);
        assertEq(stake.balanceOf(address(this)), cupStakeBalanceBefore);
    }

    // @notice if backfill happens after issuance fees are returned to Sense's cup multisig address, both issuance fees
    // and the stakecoin stake will go to Sense's cup multisig address
    function testBackfillScaleAfterSponsorBeforeSettlementWindowsTransfersStakecoinStakeAndFees(uint128 tBal) public {
        uint48 maturity = getValidMaturity(2021, 10);
        uint256 sponsorTargetBalanceBefore = target.balanceOf(address(alice));
        uint256 sponsorStakeBalanceBefore = stake.balanceOf(address(alice));
        uint256 cupTargetBalanceBefore = target.balanceOf(address(this));
        uint256 cupStakeBalanceBefore = stake.balanceOf(address(this));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);

        uint256 tDecimals = target.decimals();
        uint256 tBase = 10**tDecimals;
        uint256 fee = convertToBase(ISSUANCE_FEE, tDecimals).fmul(tBal, tBase); // 1 target
        bob.doIssue(address(adapter), maturity, tBal);

        hevm.warp(maturity + SPONSOR_WINDOW + 1 seconds);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 2 * tBase;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , , uint256 mscale, , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 sponsorTargetBalanceAfter = target.balanceOf(address(alice));
        uint256 sponsorStakeBalanceAfter = stake.balanceOf(address(alice));
        assertEq(sponsorTargetBalanceAfter, sponsorTargetBalanceBefore);
        assertEq(sponsorStakeBalanceAfter, sponsorStakeBalanceBefore - convertToBase(STAKE_SIZE, stake.decimals()));
        uint256 cupTargetBalanceAfter = target.balanceOf(address(this));
        uint256 cupStakeBalanceAfter = stake.balanceOf(address(this));
        assertEq(cupTargetBalanceAfter, cupTargetBalanceBefore + fee);
        assertEq(cupStakeBalanceAfter, cupStakeBalanceBefore + convertToBase(STAKE_SIZE, stake.decimals()));
    }

    /* ========== setAdapter() tests ========== */
    function testCantSetAdapterIfNotTrusted() public {
        try bob.doSetAdapter(address(adapter), false) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }

    function testCantSetAdapterWithSameValue() public {
        try divider.setAdapter(address(adapter), true) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.ExistingValue);
        }
    }

    function testSetAdapterFirst() public {
        // check first adapter added on TestHelper.sol has ID 1
        assertEq(divider.lastAdapterId(), 1);
        assertEq(divider.adapterIDs(address(adapter)), 1);
        assertEq(divider.adapterAddresses(1), address(adapter));
    }

    function testSetAdapter() public {
        MockAdapter aAdapter = new MockAdapter();
        uint256 lastAdapterId = divider.lastAdapterId();

        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), lastAdapterId + 1);
        assertEq(divider.adapterAddresses(lastAdapterId + 1), address(aAdapter));
    }

    function testSetAdapterBackOnKeepsExistingId() public {
        MockAdapter aAdapter = new MockAdapter();
        uint256 lastAdapterId = divider.lastAdapterId();

        // set adapter on
        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), lastAdapterId + 1);
        assertEq(divider.adapterAddresses(lastAdapterId + 1), address(aAdapter));

        // set adapter off
        divider.setAdapter(address(aAdapter), false);

        // create new adapter
        MockAdapter bAdapter = new MockAdapter();
        divider.setAdapter(address(bAdapter), true);
        assertTrue(divider.adapters(address(bAdapter)));
        assertEq(divider.adapterIDs(address(bAdapter)), lastAdapterId + 2);
        assertEq(divider.adapterAddresses(lastAdapterId + 2), address(bAdapter));

        // set adapter back on
        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), lastAdapterId + 1);
        assertEq(divider.adapterAddresses(lastAdapterId + 1), address(aAdapter));
    }

    /* ========== addAdapter() tests ========== */
    function testCantAddAdapterWhenNotPermissionless() public {
        divider.setAdapter(address(adapter), false);
        try bob.doAddAdapter(address(adapter)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OnlyPermissionless);
        }
    }

    function testCantAddAdapterWithSameValue() public {
        divider.setPermissionless(true);
        try bob.doAddAdapter(address(adapter)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.ExistingValue);
        }
    }

    function testCantAddAdapterIfPaused() public {
        divider.setPermissionless(true);
        divider.setPaused(true);
        try bob.doAddAdapter(address(adapter)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testAddAdapter() public {
        divider.setPermissionless(true);
        divider.setAdapter(address(adapter), false);
        bob.doAddAdapter(address(adapter));
        assertEq(divider.adapterIDs(address(adapter)), 1);
        assertEq(divider.adapterAddresses(1), address(adapter));
        assertTrue(divider.adapters(address(adapter)));
    }
}
