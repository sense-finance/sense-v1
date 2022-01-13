// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Levels } from "@sense-finance/v1-utils/src/libs/Levels.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { User } from "./test-helpers/User.sol";
import { MockAdapter, MockBaseAdapter } from "./test-helpers/mocks/MockAdapter.sol";
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
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    function testCantInitSeriesNotEnoughStakeAllowance() public {
        alice.doApprove(address(stake), address(periphery), 0);
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    function testCantInitSeriesAdapterNotEnabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        divider.setAdapter(address(adapter), false);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantInitSeriesIfAlreadyExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
            uint256 nextMonthDate = DateTimeFull.addMonths(block.timestamp, i);
            nextMonthDate = getValidMaturity(DateTimeFull.getYear(nextMonthDate), DateTimeFull.getMonth(nextMonthDate));
            (address zero, address claim) = sponsorSampleSeries(address(alice), nextMonthDate);
            hevm.warp(block.timestamp + 1 days);
            assertTrue(address(zero) != address(0));
            assertTrue(address(claim) != address(0));
        }
        uint256 lastDate = DateTimeFull.addMonths(block.timestamp, SERIES_TO_INIT + 1);
        lastDate = getValidMaturity(DateTimeFull.getYear(lastDate), DateTimeFull.getMonth(lastDate));
        try alice.doSponsorSeries(address(adapter), lastDate) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesWithMaturityBeforeTimestamp() public {
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 8, 1, 0, 0, 0);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesLessThanMinMaturity() public {
        hevm.warp(1631923200);
        // 18-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesMoreThanMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2022, 1, 1, 0, 0, 0);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesIfModeInvalid() public {
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            4,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Tuesday
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testCantInitSeriesIfNotTopWeek() public {
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            1,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 5, 0, 0, 0); // Tuesday
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidMaturity);
        }
    }

    function testInitSeriesWeekly() public {
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            1,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        hevm.warp(1631664000); // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday
        (address zero, address claim) = alice.doSponsorSeries(address(adapter), maturity);

        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
        assertEq(ERC20(zero).name(), "Compound Dai 10-2021 Zero #2 by Sense");
        assertEq(ERC20(zero).symbol(), "zcDAI:10-2021:#2");
        assertEq(ERC20(claim).name(), "Compound Dai 10-2021 Claim #2 by Sense");
        assertEq(ERC20(claim).symbol(), "ccDAI:10-2021:#2");
    }

    function testCantInitSeriesIfPaused() public {
        divider.setPaused(true);
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doSponsorSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testInitSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
        assertEq(ERC20(zero).name(), "Compound Dai 10-2021 Zero #1 by Sense");
        assertEq(ERC20(zero).symbol(), "zcDAI:10-2021:#1");
        assertEq(ERC20(claim).name(), "Compound Dai 10-2021 Claim #1 by Sense");
        assertEq(ERC20(claim).symbol(), "ccDAI:10-2021:#1");
    }

    function testInitSeriesWithdrawStake() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
            uint256 nextMonthDate = DateTimeFull.addMonths(block.timestamp, i);
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
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        sponsorSampleSeries(address(alice), maturity);
    }

    function testInitSeriesOnMaxMaturity() public {
        hevm.warp(1631664000);
        // 15-09-21 00:00 UTC
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 12, 1, 0, 0, 0);
        sponsorSampleSeries(address(alice), maturity);
    }

    /* ========== settleSeries() tests ========== */

    function testCantSettleSeriesIfDisabledAdapter() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        divider.setAdapter(address(adapter), false);
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantSettleSeriesAlreadySettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        try bob.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfNotSponsorCutoffTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        try bob.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfSponsorAndCutoffTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantSettleSeriesIfNotSponsorAndSponsorTime() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doSettleSeries(address(adapter), maturity) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testSettleSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSponsorWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMinLimit() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.subSeconds(maturity, SPONSOR_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndOnSponsorWindowMaxLimit() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfSponsorAndSettlementWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        alice.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesIfNotSponsorAndSettlementWindow() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW));
        bob.doSettleSeries(address(adapter), maturity);
    }

    function testSettleSeriesStakeIsTransferredIfSponsor() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(address(alice));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(address(alice));
        assertEq(beforeBalance, afterBalance);
    }

    function testSettleSeriesStakeIsTransferredIfNotSponsor() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 beforeBalance = stake.balanceOf(address(bob));
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + 1 seconds));
        bob.doSettleSeries(address(adapter), maturity);
        uint256 afterBalance = stake.balanceOf(address(bob));
        assertEq(afterBalance, beforeBalance + convertToBase(STAKE_SIZE, stake.decimals()));
    }

    function testSettleSeriesWithMockBaseAdapter() public {
        divider.setPermissionless(true);
        MockBaseAdapter aAdapter = new MockBaseAdapter(
            address(divider),
            address(target),
            ORACLE,
            1e18,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL
        );
        divider.addAdapter(address(aAdapter));
        uint256 maturity = getValidMaturity(2021, 10);
        User(alice).doSponsorSeries(address(aAdapter), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(aAdapter), maturity);
    }

    function testFuzzSettleSeriesFeesAreTransferredIfSponsor(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

    function testFuzzSettleSeriesFeesAreTransferredIfNotSponsor(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        divider.setGuard(address(adapter), aliceBalance * 2);
        try alice.doIssue(address(adapter), maturity, aliceBalance + 1) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    function testCantIssueNotEnoughAllowance() public {
        uint256 aliceBalance = target.balanceOf(address(alice));
        alice.doApprove(address(target), address(divider), 0);
        divider.setGuard(address(adapter), aliceBalance);
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        bob.doApprove(address(target), address(periphery), 0);
        try alice.doIssue(address(adapter), maturity, aliceBalance) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, arithmeticError);
        }
    }

    function testCantIssueIfSeriesSettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 guard = divider.guards(address(adapter));
        uint256 targetBalance = target.balanceOf(address(alice));
        divider.setGuard(address(adapter), targetBalance);
        alice.doIssue(address(adapter), maturity, targetBalance);
        try bob.doIssue(address(adapter), maturity, 1e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.GuardCapReached);
        }
    }

    function testCantIssueIfIssuanceFeeExceedsCap() public {
        divider.setPermissionless(true);
        MockAdapter aAdapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            1e18,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.addAdapter(address(aAdapter));
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doIssue(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testIssueLevelRestrictions() public {
        // Restrict issuance, enable all other lifecycle methods
        uint16 level = 2**0 + 2**2 + 2**3 + 2**4;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);

        bob.doApprove(address(target), address(adapter), type(uint256).max);

        // Should be possible to init series
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        // Can't issue directly through the divider
        try bob.doIssue(address(adapter), maturity, 1e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.IssuanceRestricted);
        }

        // Can issue through adapter
        bob.doAdapterIssue(address(adapter), maturity, 1e18);

        // It should still be possible to combine
        bob.doCombine(address(adapter), maturity, ERC20(claim).balanceOf(address(bob)));
    }

    function testFuzzIssue(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBase = 10**target.decimals();
        uint256 fee = convertToBase(ISSUANCE_FEE, target.decimals()).fmul(tBal, tBase); // 1 target
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        alice.doIssue(address(adapter), maturity, tBal);
        // Formula = newBalance.fmul(scale)
        (, uint256 lscale) = adapter.lscale();
        uint256 mintedAmount = (tBal - fee).fmul(lscale, FixedMath.WAD);
        assertEq(ERC20(zero).balanceOf(address(alice)), mintedAmount);
        assertEq(ERC20(claim).balanceOf(address(alice)), mintedAmount);
        assertEq(target.balanceOf(address(alice)), tBalanceBefore - tBal);
    }

    function testIssueIfMoreThanCapButGuardedDisabled() public {
        uint256 aliceBalance = target.balanceOf(address(alice));
        divider.setGuard(address(adapter), aliceBalance - 1);
        divider.setGuarded(false);
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 amount = divider.guards(address(target)) + 1;
        alice.doIssue(address(adapter), maturity, amount);
    }

    function testFuzzIssueMultipleTimes(uint128 bal) public {
        // if issuing multiple times with bal = 0, the 2nd issue will fail on _reweightLScale because
        // it will attempt to do a division by 0.
        bal = fuzzWithBounds(bal, 1000);
        uint256 maturity = getValidMaturity(2021, 10);
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
        (, uint256 lscale) = adapter.lscale();
        uint256 mintedAmount = (tBal - fee).fmul(lscale, FixedMath.WAD);
        assertEq(ERC20(zero).balanceOf(address(alice)), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(ERC20(claim).balanceOf(address(alice)), mintedAmount.fmul(4 * tBase, tBase));
        assertEq(target.balanceOf(address(alice)), tBalanceBefore - tBal.fmul(4 * tBase, tBase));
    }

    function testIssueReweightScale() public {
        uint256 tBal = 1e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        alice.doIssue(address(adapter), maturity, tBal);
        uint256 lscaleFirst = divider.lscales(address(adapter), maturity, address(alice));

        hevm.warp(block.timestamp + 7 days);
        uint256 lscaleSecond = divider.lscales(address(adapter), maturity, address(alice));
        alice.doIssue(address(adapter), maturity, tBal);
        uint256 scaleAfterThrid = adapter.scale();

        hevm.warp(block.timestamp + 7 days);
        uint256 lscaleThird = divider.lscales(address(adapter), maturity, address(alice));
        alice.doIssue(address(adapter), maturity, tBal * 5);
        uint256 lscaleFourth = divider.lscales(address(adapter), maturity, address(alice));

        assertEq(lscaleFirst, lscaleSecond);

        // Exact mean
        assertEq((lscaleSecond + scaleAfterThrid) / 2, lscaleThird);

        // Weighted
        assertEq((lscaleThird * 2 + adapter.scale() * 5) / 7, lscaleFourth);
    }

    /* ========== combine() tests ========== */

    function testCantCombineAdapterDisabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doCombine(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testCantCombineIfProperLevelIsntSet() public {
        // Restrict combine, enable all other lifecycle methods
        uint16 level = 2**0 + 2**1 + 2**3 + 2**4;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        bob.doIssue(address(adapter), maturity, 1e18);

        try bob.doCombine(address(adapter), maturity, ERC20(claim).balanceOf(address(bob))) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.CombineRestricted);
        }

        // Collect still works
        hevm.warp(block.timestamp + 1 days);
        uint256 collected = bob.doCollect(claim);
        assertGt(collected, 0);

        // Can combine through adapter
        uint256 balance = ERC20(claim).balanceOf(address(bob));
        bob.doTransfer(address(zero), address(adapter), balance);
        bob.doTransfer(address(claim), address(adapter), balance);
        uint256 combined = bob.doAdapterCombine(address(adapter), maturity, balance);
        assertGt(combined, 0);
    }

    function testFuzzCantCombineNotEnoughBalance(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 issued = bob.doIssue(address(adapter), maturity, tBal);
        try bob.doCombine(address(adapter), maturity, issued + 1) {
            fail();
        } catch (bytes memory error) {
            // Does not return any error message
        }
    }

    function testFuzzCantCombineNotEnoughAllowance(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        uint256 issued = bob.doIssue(address(adapter), maturity, tBal);
        bob.doApprove(address(target), address(periphery), 0);
        try bob.doCombine(address(adapter), maturity, issued + 1) {
            fail();
        } catch (bytes memory error) {
            // Does not return any error message
        }
    }

    function testFuzzCombine(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 1 days);
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 zBalanceBefore = ERC20(zero).balanceOf(address(bob));
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 combined = bob.doCombine(address(adapter), maturity, zBalanceBefore);
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        uint256 zBalanceAfter = ERC20(zero).balanceOf(address(bob));
        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        assertEq(zBalanceAfter, 0);
        assertEq(cBalanceAfter, 0);
        assertClose((combined).fmul(lscale, FixedMath.WAD), zBalanceBefore); // check includes collected target
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale, FixedMath.WAD), zBalanceBefore);
    }

    function testFuzzCombineAtMaturity(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

        assertEq(zBalanceAfter, 0);
        assertEq(cBalanceAfter, 0);
        assertClose((tBalanceAfter - tBalanceBefore).fmul(lscale, FixedMath.WAD), zBalanceBefore);
    }

    /* ========== redeemZero() tests ========== */
    function testCantRedeemZeroDisabledAdapter() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 balance = 1e18;
        try alice.doRedeemZero(address(adapter), maturity, balance) {
            fail();
        } catch Error(string memory error) {
            // The settled check will fail if the Series does not exist
            assertEq(error, Errors.NotSettled);
        }
    }

    function testCantRedeemZeroSeriesNotSettled() public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        try alice.doRedeemZero(address(adapter), maturity, 100e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Paused);
        }
    }

    function testFuzzRedeemZero(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000);
        uint256 maturity = getValidMaturity(2021, 10);
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
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        uint256 redeemed = balanceToRedeem.fdiv(mscale, FixedMath.WAD);
        // Amount of Zeros burned == underlying amount
        assertClose(redeemed.fmul(mscale, FixedMath.WAD), zBalanceBefore);
        assertEq(zBalanceBefore, zBalanceAfter + balanceToRedeem);
    }

    function testRedeemZeroBalanceIsZero() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 tBalanceBefore = target.balanceOf(address(alice));
        uint256 balance = 0;
        alice.doRedeemZero(address(adapter), maturity, balance);
        uint256 tBalanceAfter = target.balanceOf(address(alice));
        assertEq(tBalanceAfter, tBalanceBefore);
    }

    function testRedeemZeroPositiveTiltNegativeScale() public {
        // Reserve 10% of principal for Claims
        uint64 tilt = 0.1e18;
        // The Targeted redemption value Alice will send Bob wants, in Underlying
        uint256 intendedRedemptionValue = 50e18;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            tilt,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        // Sanity check
        assertEq(adapter.tilt(), tilt);

        adapter.setScale(1e18);

        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);

        uint256 tBal = 100e18;
        alice.doIssue(address(adapter), maturity, tBal);

        // Alice transfers Zeros that would ideally redeem for 50 Underlying at maturity
        // 50 = zero bal * 1 - tilt
        alice.doTransfer(address(zero), address(bob), intendedRedemptionValue.fdiv(1e18 - tilt, 1e18));

        uint256 tBalanceBeforeRedeem = ERC20(target).balanceOf(address(bob));
        uint256 zeroBalanceBefore = ERC20(zero).balanceOf(address(bob));
        hevm.warp(maturity);
        // Set scale to 90% of its initial value
        adapter.setScale(0.9e18);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 redeemed = bob.doRedeemZero(address(adapter), maturity, zeroBalanceBefore);

        // Even though the scale has gone down, Zeros should redeem for 100% of their intended redemption
        assertClose(redeemed, intendedRedemptionValue.fdiv(adapter.scale(), 1e18), 10);

        uint256 tBalanceAfterRedeem = ERC20(target).balanceOf(address(bob));
        // Redeemed amount should match the amount of Target bob got back
        assertEq(tBalanceAfterRedeem - tBalanceBeforeRedeem, redeemed);

        // Bob should have gained Target comensurate with the entire intended Zero redemption value
        assertClose(
            tBalanceBeforeRedeem + intendedRedemptionValue.fdiv(adapter.scale(), 1e18),
            tBalanceAfterRedeem,
            10
        );
    }

    function testRedeemZeroNoTiltNegativeScale() public {
        // Sanity check
        assertEq(adapter.tilt(), 0);
        // The Targeted redemption value Alice will send Bob wants, in Underlying
        uint256 intendedRedemptionValue = 50e18;

        adapter.setScale(1e18);

        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);

        uint256 tBal = 100e18;
        alice.doIssue(address(adapter), maturity, tBal);

        // Alice transfers Zeros that would ideally redeem for 50 Underlying at maturity
        // 50 = zero bal * 1 - tilt
        alice.doTransfer(address(zero), address(bob), intendedRedemptionValue.fdiv(1e18 - adapter.tilt(), 1e18));

        uint256 tBalanceBeforeRedeem = ERC20(target).balanceOf(address(bob));
        uint256 zeroBalanceBefore = ERC20(zero).balanceOf(address(bob));
        hevm.warp(maturity);
        // Set scale to 90% of its initial value
        adapter.setScale(0.9e18);
        alice.doSettleSeries(address(adapter), maturity);
        uint256 redeemed = bob.doRedeemZero(address(adapter), maturity, zeroBalanceBefore);

        // Without any Claim principal to cut into, Zero holders should be down to 90% of their intended redemption
        assertClose(redeemed, intendedRedemptionValue.fdiv(adapter.scale(), 1e18).fmul(0.9e18, 1e18), 10);

        uint256 tBalanceAfterRedeem = ERC20(target).balanceOf(address(bob));
        // Redeemed amount should match the amount of Target bob got back
        assertEq(tBalanceAfterRedeem - tBalanceBeforeRedeem, redeemed);

        // Bob should have gained Target comensurate with the 90% of his intended Zero redemption value
        assertClose(
            tBalanceBeforeRedeem + intendedRedemptionValue.fdiv(adapter.scale(), 1e18).fmul(0.9e18, 1e18),
            tBalanceAfterRedeem,
            10
        );
    }

    function testRedeenZeroHookIsntCalledIfProperLevelIsntSet() public {
        // Enable all Divider lifecycle methods, but not the adapter zero redeem hook
        uint16 level = 2**0 + 2**1 + 2**2 + 2**3 + 2**4;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        bob.doIssue(address(adapter), maturity, 1e18);

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        bob.doRedeemZero(address(adapter), maturity, ERC20(zero).balanceOf(address(bob)));
        assertEq(adapter.onZeroRedeemCalls(), 0);
    }

    function testRedeenZeroHookIsCalledIfProperLevelIsntSet() public {
        uint16 level = 2**0 + 2**1 + 2**2 + 2**3 + 2**4 + 2**5;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, ) = sponsorSampleSeries(address(alice), maturity);
        bob.doIssue(address(adapter), maturity, 1e18);

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        bob.doRedeemZero(address(adapter), maturity, ERC20(zero).balanceOf(address(bob)));
        assertEq(adapter.onZeroRedeemCalls(), 1);
    }

    /* ========== redeemClaim() tests ========== */
    function testRedeemClaimPositiveTiltPositiveScale() public {
        // Reserve 10% of principal for Claims
        uint64 tilt = 0.1e18;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            tilt,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        // Can collect normally
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, 100e18);
        hevm.warp(block.timestamp + 1 days);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));
        uint256 collected = bob.doCollect(claim);
        assertTrue(adapter.tBalance(address(bob)) > 0);

        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD) - cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        collected = bob.doCollect(claim);
        assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        uint256 maxscale;
        (, , , , , mscale, maxscale, , ) = divider.series(address(adapter), maturity);
        uint256 redeemed = (cBalanceAfter * FixedMath.WAD) /
            maxscale -
            (cBalanceAfter * (FixedMath.WAD - tilt)) /
            mscale;
        assertEq(target.balanceOf(address(bob)), tBalanceAfter + collected + redeemed);
        assertClose(adapter.tBalance(address(bob)), 0);
        collected = bob.doCollect(claim); // try collecting after redemption
        assertEq(collected, 0);
    }

    function testRedeemClaimPositiveTiltNegativeScale() public {
        // Reserve 10% of principal for Claims
        uint64 tilt = 0.1e18;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            tilt,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);

        // Sanity check
        assertEq(adapter.tilt(), 0.1e18);

        // Reserve 10% of principal for Claims
        adapter.setScale(1e18);
        // Sanity check
        assertEq(adapter.scale(), 1e18);

        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        uint256 tBal = 100e18;
        bob.doIssue(address(adapter), maturity, tBal);
        assertTrue(adapter.tBalance(address(bob)) > 0);

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
        assertEq(adapter.tBalance(address(bob)), 0);
        collected = bob.doCollect(claim); // try collecting after redemption
        assertEq(collected, 0);
    }

    /* ========== collect() tests ========== */
    function testCantCollectDisabledAdapter() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        divider.setAdapter(address(adapter), false);
        try alice.doCollect(claim) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidAdapter);
        }
    }

    function testCantCollectIfProperLevelIsntSet() public {
        // Disable collection, enable all other lifecycle methods
        uint16 level = 2**0 + 2**1 + 2**2 + 2**4;

        adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );
        divider.setAdapter(address(adapter), true);
        divider.setGuard(address(adapter), type(uint256).max);
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 initScale = adapter.scale();
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        bob.doIssue(address(adapter), maturity, 1e18);
        hevm.warp(block.timestamp + 1 days);

        // Scale has grown so there should be excess yield available
        assertTrue(initScale < adapter.scale());

        // Yet none is collected
        uint256 collected = bob.doCollect(claim);
        assertEq(collected, 0);

        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);

        // But it can be collected at maturity
        collected = bob.doCollect(claim);
        assertGt(collected, 0);

        // It should still be possible to combine
        bob.doCombine(address(adapter), maturity, ERC20(claim).balanceOf(address(bob)));
    }

    function testFuzzCantCollectIfMaturityAndNotSettled(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

    function testFuzzCantCollectIfPaused(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 maturity = getValidMaturity(2021, 10);
        try divider.collect(address(bob), address(adapter), maturity, tBal, address(bob)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OnlyClaim);
        }
    }

    function testCollectSmallTBal(uint128 tBal) public {
        tBal = 1;
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = 10**Token(claim).decimals();
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
        (, , , , , uint256 mscale, uint256 maxscale, , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 tBalNow = cBalanceBefore.fdivUp(maxscale, FixedMath.WAD); // preventive round-up towards the protocol
        uint256 tBalPrev = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        uint256 collect = tBalPrev > tBalNow ? tBalPrev - tBalNow : 0;

        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testFuzzCollect(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = 10**Token(claim).decimals();
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
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    function testFuzzCollectReward(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000, type(uint32).max);
        adapter.setScale(1e18);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
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
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdiv(cscale, FixedMath.WAD);
        assertEq(cBalanceBefore, cBalanceAfter);
        assertEq(collected, collect);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
        assertClose(rBalanceAfter, rBalanceBefore + airdrop);
    }

    function testFuzzCollectRewardMultipleUsers(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000, type(uint32).max);
        adapter.setScale(1e18);
        uint256 maturity = getValidMaturity(2021, 10);
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
                (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
                (, uint256 lvalue) = adapter.lscale();
                uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
                collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
                collect -= cBalanceBefore.fdiv(cscale, FixedMath.WAD);
            }
            assertEq(cBalanceBefore, ERC20(claim).balanceOf(address(users[i])));
            assertEq(collected, collect);
            assertEq(target.balanceOf(address(users[i])), tBalanceBefore + collected);
            assertClose(reward.balanceOf(address(users[i])), rBalanceBefore + airdrop);
        }
    }

    function testCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1000, type(uint32).max);
        adapter.setScale(1e18);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);

        alice.doIssue(address(adapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop);
        alice.doCollect(claim);
        assertTrue(adapter.tBalance(address(alice)) > 0);

        reward.mint(address(adapter), airdrop);
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        alice.doCollect(claim);

        assertEq(adapter.tBalance(address(alice)), 0);
        uint256 collected = alice.doCollect(claim); // try collecting after redemption
        assertEq(collected, 0);
    }

    function testFuzzCollectAtMaturityBurnClaimsAndDoesNotCallBurnTwice(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(maturity);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 cBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceBefore = target.balanceOf(address(bob));

        alice.doSettleSeries(address(adapter), maturity);

        uint256 collected = bob.doCollect(claim);
        if (tBal > 0) assertTrue(adapter.tBalance(address(bob)) > 0);

        uint256 cBalanceAfter = ERC20(claim).balanceOf(address(bob));
        uint256 tBalanceAfter = target.balanceOf(address(bob));
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;

        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
        assertClose(adapter.tBalance(address(bob)), 1);
    }

    function testFuzzCollectBeforeMaturityAfterEmergencyDoesNotReplaceBackfilled(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        divider.setAdapter(address(adapter), false); // emergency stop
        uint256 newScale = 20e17;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales); // fix invalid scale value
        divider.setAdapter(address(adapter), true); // re-enable adapter after emergency
        bob.doCollect(claim);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        // TODO: check .scale() is not called (like to add the lscale). We can't?
    }

    function testFuzzCollectBeforeMaturityAndSettled(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
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
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, 0);
        assertEq(tBalanceAfter, tBalanceBefore + collected); // TODO: double check!
    }

    // test transferring claims to user calls collect()
    function testFuzzCollectTransferAndCollect(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        uint256 claimBaseUnit = 10**Token(claim).decimals();
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);

        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 blscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 btBalanceBefore = target.balanceOf(address(bob));

        bob.doTransfer(address(claim), address(alice), bcBalanceBefore); // collects and transfer

        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;

        // bob
        uint256 btBalanceAfter = target.balanceOf(address(bob));
        uint256 bcollected = btBalanceAfter - btBalanceBefore;

        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 bcollect = bcBalanceBefore.fdiv(blscale, FixedMath.WAD);
        bcollect -= bcBalanceBefore.fdivUp(cscale, FixedMath.WAD);

        assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        assertEq(btBalanceAfter, btBalanceBefore + bcollected);
        assertEq(ERC20(claim).balanceOf(address(alice)), acBalanceBefore + bcBalanceBefore);
    }

    // test transferring claims to a user calls collect()
    // it also checks that receiver receives corresp. target collected from the claims he already had
    function testFuzzCollectTransferAndCollectWithReceiverHoldingClaims(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e10);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        alice.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);

        // alice
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 atBalanceBefore = target.balanceOf(address(alice));

        // bob
        uint256 blscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 btBalanceBefore = target.balanceOf(address(bob));

        bob.doTransfer(address(claim), address(alice), bcBalanceBefore); // collects and transfer
        uint256 alscale = divider.lscales(address(adapter), maturity, address(alice));
        alice.doCollect(claim);

        uint256 cscale;
        {
            (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
            (, uint256 lvalue) = adapter.lscale();
            cscale = block.timestamp >= maturity ? mscale : lvalue;
        }

        {
            // alice
            uint256 atBalanceAfter = target.balanceOf(address(alice));
            uint256 acollected = atBalanceAfter - atBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 acollect = (acBalanceBefore + bcBalanceBefore).fdiv(alscale, FixedMath.WAD);
            acollect -= (acBalanceBefore + bcBalanceBefore).fdivUp(cscale, FixedMath.WAD);
            assertEq(acollected, acollect);
            assertEq(atBalanceAfter, atBalanceBefore + acollected);
            assertEq(ERC20(claim).balanceOf(address(alice)), acBalanceBefore + bcBalanceBefore);
        }

        {
            // bob
            uint256 btBalanceAfter = target.balanceOf(address(bob));
            uint256 bcollected = btBalanceAfter - btBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 bcollect = bcBalanceBefore.fdiv(blscale, FixedMath.WAD);
            bcollect -= bcBalanceBefore.fdivUp(cscale, FixedMath.WAD);

            assertEq(bcollected, bcollect);
            assertEq(btBalanceAfter, btBalanceBefore + bcollected);
            assertEq(ERC20(claim).balanceOf(address(bob)), 0);
        }
    }

    function testFuzzCollectTransferLessThanBalanceAndCollectWithReceiverHoldingClaims(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        hevm.warp(block.timestamp + 1 days);
        bob.doIssue(address(adapter), maturity, tBal);
        alice.doIssue(address(adapter), maturity, tBal);
        hevm.warp(block.timestamp + 15 days);

        // alice
        uint256 acBalanceBefore = ERC20(claim).balanceOf(address(alice));
        uint256 atBalanceBefore = target.balanceOf(address(alice));

        // bob
        uint256 blscale = divider.lscales(address(adapter), maturity, address(bob));
        uint256 bcBalanceBefore = ERC20(claim).balanceOf(address(bob));
        uint256 btBalanceBefore = target.balanceOf(address(bob));

        uint256 transferValue = tBal / 2;
        bob.doTransfer(address(claim), address(alice), transferValue); // collects and transfer
        uint256 alscale = divider.lscales(address(adapter), maturity, address(alice));
        alice.doCollect(claim);

        uint256 cscale;
        {
            (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
            (, uint256 lvalue) = adapter.lscale();
            cscale = block.timestamp >= maturity ? mscale : lvalue;
        }

        {
            // alice
            uint256 atBalanceAfter = target.balanceOf(address(alice));
            uint256 acollected = atBalanceAfter - atBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 acollect = (acBalanceBefore + transferValue).fdiv(alscale, FixedMath.WAD);
            acollect -= (acBalanceBefore + transferValue).fdivUp(cscale, FixedMath.WAD);

            assertEq(acollected, acollect);
            assertEq(atBalanceAfter, atBalanceBefore + acollected);
            assertEq(ERC20(claim).balanceOf(address(alice)), acBalanceBefore + transferValue);
        }

        {
            // bob
            uint256 btBalanceAfter = target.balanceOf(address(bob));
            uint256 bcollected = btBalanceAfter - btBalanceBefore;

            // Formula: collect = tBal / lscale - tBal / cscale
            uint256 bcollect = bcBalanceBefore.fdiv(blscale, FixedMath.WAD);
            bcollect -= bcBalanceBefore.fdivUp(cscale, FixedMath.WAD);

            assertEq(bcollected, bcollect);
            assertEq(ERC20(claim).balanceOf(address(bob)), bcBalanceBefore - transferValue);
            assertEq(btBalanceAfter, btBalanceBefore + bcollected);
        }
    }

    function testFuzzCollectTransferToMyselfAndCollect(uint128 tBal) public {
        tBal = fuzzWithBounds(tBal, 1e12);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
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

        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        (, uint256 lvalue) = adapter.lscale();
        uint256 cscale = block.timestamp >= maturity ? mscale : lvalue;
        // Formula: collect = tBal / lscale - tBal / cscale
        uint256 collect = cBalanceBefore.fdiv(lscale, FixedMath.WAD);
        collect -= cBalanceBefore.fdivUp(cscale, FixedMath.WAD);
        assertEq(collected, collect);
        assertEq(cBalanceAfter, cBalanceBefore);
        assertEq(tBalanceAfter, tBalanceBefore + collected);
    }

    /* ========== backfillScale() tests ========== */
    function testCantBackfillScaleSeriesDoesntExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        uint256 tBal = 100 * tBase;
        try divider.backfillScale(address(adapter), maturity, tBal, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SeriesDoesntExists);
        }
    }

    function testCantBackfillScaleBeforeCutoffAndAdapterEnabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        (, , , , uint256 iscale, , , , ) = divider.series(address(adapter), maturity);
        try divider.backfillScale(address(adapter), maturity, iscale + 1, usrs, lscales) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.OutOfWindowBoundaries);
        }
    }

    function testCantBackfillScaleSeriesNotGov() public {
        uint256 maturity = getValidMaturity(2021, 10);
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

    function testBackfillScale() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(DateTimeFull.addSeconds(maturity, SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds));
        uint256 newScale = 1.1e18;
        usrs.push(address(alice));
        usrs.push(address(bob));
        lscales.push(5e17);
        lscales.push(4e17);
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 lscale = divider.lscales(address(adapter), maturity, address(alice));
        assertEq(lscale, lscales[0]);
        lscale = divider.lscales(address(adapter), maturity, address(bob));
        assertEq(lscale, lscales[1]);
    }

    function testBackfillScaleBeforeCutoffAndAdapterDisabled() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        hevm.warp(maturity);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 1.5e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
    }

    // @notice if backfill happens while adapter is NOT disabled it is because the current timestamp is > cutoff so stakecoin stake and fees are to the Sense's cup multisig address
    function testFuzzBackfillScaleAfterCutoffAdapterEnabledTransfersStakeAmountAndFees(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        assertEq(target.balanceOf(address(alice)), sponsorTargetBalanceBefore);
        assertEq(
            stake.balanceOf(address(alice)),
            sponsorStakeBalanceBefore - convertToBase(STAKE_SIZE, stake.decimals())
        );
        assertEq(target.balanceOf(address(this)), cupTargetBalanceBefore + fee);
        assertEq(stake.balanceOf(address(this)), cupStakeBalanceBefore + convertToBase(STAKE_SIZE, stake.decimals()));
    }

    // @notice if backfill happens while adapter is disabled stakecoin stake is transferred to Sponsor and fees are to the Sense's cup multisig address
    // no matter that the current timestamp is > cutoff
    function testFuzzBackfillScaleAfterCutoffAdapterDisabledTransfersStakeAmountAndFees(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

        hevm.warp(maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW + 1 seconds);
        divider.setAdapter(address(adapter), false);
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        assertEq(target.balanceOf(address(alice)), sponsorTargetBalanceBefore);
        assertEq(stake.balanceOf(address(alice)), sponsorStakeBalanceBefore);
        assertEq(target.balanceOf(address(this)), cupTargetBalanceBefore + fee);
        assertEq(stake.balanceOf(address(this)), cupStakeBalanceBefore);
    }

    // @notice if backfill happens before the maturity and sponsor window, stakecoin stake is transferred to the
    // sponsor and issuance fees are returned to Sense's cup multisig address
    function testFuzzBackfillScaleBeforeSponsorWindowTransfersStakeAmountAndFees(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        assertEq(target.balanceOf(address(alice)), sponsorTargetBalanceBefore);
        assertEq(stake.balanceOf(address(alice)), sponsorStakeBalanceBefore);
        assertEq(target.balanceOf(address(this)), cupTargetBalanceBefore + fee);
        assertEq(stake.balanceOf(address(this)), cupStakeBalanceBefore);
    }

    // @notice if backfill happens while adapter is disabled, stakecoin stake is transferred to Sponsor and fees are to the Sense's cup multisig address
    // no matter that the current timestamp is > SPONSOR WINDOW
    function testFuzzBackfillScaleAfterSponsorBeforeSettlementWindowsTransfersStakecoinStakeAndFees(uint128 tBal)
        public
    {
        uint256 maturity = getValidMaturity(2021, 10);
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
        uint256 newScale = 2e18;
        divider.backfillScale(address(adapter), maturity, newScale, usrs, lscales);
        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, newScale);
        uint256 sponsorTargetBalanceAfter = target.balanceOf(address(alice));
        uint256 sponsorStakeBalanceAfter = stake.balanceOf(address(alice));
        assertEq(sponsorTargetBalanceAfter, sponsorTargetBalanceBefore);
        assertEq(sponsorStakeBalanceAfter, sponsorStakeBalanceBefore);
        uint256 cupTargetBalanceAfter = target.balanceOf(address(this));
        uint256 cupStakeBalanceAfter = stake.balanceOf(address(this));
        assertEq(cupTargetBalanceAfter, cupTargetBalanceBefore + fee);
        assertEq(cupStakeBalanceAfter, cupStakeBalanceBefore);
    }

    function testFuzzBackfillOnlyLScale(uint128 tBal) public {
        uint256 maturity = getValidMaturity(2021, 10);
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

        usrs.push(address(alice));
        usrs.push(address(bob));
        lscales.push(5e17);
        lscales.push(4e17);
        divider.backfillScale(address(adapter), maturity, 0, usrs, lscales);

        (, , , , , uint256 mscale, , , ) = divider.series(address(adapter), maturity);
        assertEq(mscale, 0);
        assertEq(target.balanceOf(address(alice)), sponsorTargetBalanceBefore);
        assertEq(
            stake.balanceOf(address(alice)),
            sponsorStakeBalanceBefore - convertToBase(STAKE_SIZE, stake.decimals())
        );
        assertEq(target.balanceOf(address(this)), cupTargetBalanceBefore);
        assertEq(stake.balanceOf(address(this)), cupStakeBalanceBefore);

        uint256 lscale = divider.lscales(address(adapter), maturity, address(alice));
        assertEq(lscale, lscales[0]);
        lscale = divider.lscales(address(adapter), maturity, address(bob));
        assertEq(lscale, lscales[1]);
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
        assertEq(divider.adapterCounter(), 1);
        assertEq(divider.adapterIDs(address(adapter)), 1);
        assertEq(divider.adapterAddresses(1), address(adapter));
    }

    function testSetAdapter() public {
        MockAdapter aAdapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        uint256 adapterCounter = divider.adapterCounter();

        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));
    }

    function testSetAdapterBackOnKeepsExistingId() public {
        MockAdapter aAdapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        uint256 adapterCounter = divider.adapterCounter();

        // set adapter on
        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));

        // set adapter off
        divider.setAdapter(address(aAdapter), false);

        // create new adapter
        MockAdapter bAdapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.setAdapter(address(bAdapter), true);
        assertTrue(divider.adapters(address(bAdapter)));
        assertEq(divider.adapterIDs(address(bAdapter)), adapterCounter + 2);
        assertEq(divider.adapterAddresses(adapterCounter + 2), address(bAdapter));

        // set adapter back on
        divider.setAdapter(address(aAdapter), true);
        assertTrue(divider.adapters(address(aAdapter)));
        assertEq(divider.adapterIDs(address(aAdapter)), adapterCounter + 1);
        assertEq(divider.adapterAddresses(adapterCounter + 1), address(aAdapter));
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
