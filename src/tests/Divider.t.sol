pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "../Divider.sol";
import "./test-helpers/TestToken.sol";
import "./test-helpers/TestFeed.sol";
import "../external/DateTime.sol";

interface Hevm {
    function warp(uint256) external;
}

contract TokenUser {
    TestToken token; // stable token
    Divider divider;

    function setToken(TestToken _token) public {
        token = _token;
    }

    function setDivider(Divider _divider) public {
        divider = _divider;
    }

    function doTransferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint256 amount) public returns (bool) {
        return token.transfer(to, amount);
    }

    function doApprove(address recipient, uint256 amount) public returns (bool) {
        return token.approve(recipient, amount);
    }

    function doAllowance(address owner, address spender) public view returns (uint256) {
        return token.allowance(owner, spender);
    }

    function doBalanceOf(address who) public view returns (uint256) {
        return token.balanceOf(who);
    }

    function doApprove(address guy) public returns (bool) {
        return token.approve(guy, type(uint256).max);
    }

    function doMint(uint256 wad) public {
        token.mint(address(this), wad);
    }

    function doMint(address guy, uint256 wad) public {
        token.mint(guy, wad);
    }

    function doSetFeed(address feed, bool isOn) public {
        divider.setFeed(feed, true);
    }

    function doInitSeries(address feed, uint256 maturity) public returns (address zero, address claim) {
        return divider.initSeries(feed, maturity);
    }

    function doSettleSeries(address feed, uint256 maturity) public {
        return divider.settleSeries(feed, maturity);
    }
}

contract DividerTest is DSTest {
    Divider divider;
    TestFeed feed;
    TestToken stableToken;
    TestToken targetToken;
    TokenUser user1;
    Hevm hevm;

    uint256 public constant SERIES_STAKE_AMOUNT = 1e18; // Hardcoded value at least for v1.

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1630454400); // 01-09-21 00:00 UTC
        stableToken = new TestToken("Stable Token", "ST");
        targetToken = new TestToken("Compound Dai", "cDAI");
        feed = new TestFeed(address(targetToken), "Compound Dai Yield", "cDAI-yield");
        user1 = new TokenUser();
        user1.setToken(stableToken);
        divider = new Divider(address(user1), address(stableToken));
        user1.setDivider(divider);
        user1.doSetFeed(address(feed), true);
    }

    // initSeries() tests
    function testFailInitSeriesNotEnoughStakeAllowance() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = divider.initSeries(address(feed), maturity);
    }

    function testFailInitSeriesFeedNotEnabled() public {
        user1.doApprove(address(divider));
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = divider.initSeries(address(feed), maturity);
    }

    function testFailInitSeriesIfAlreadyExists() public {
        uint256 maturity = getValidMaturity(2021, 9);
        initSampleSeries(maturity);
        initSampleSeries(maturity);
    }

    function testFailInitSeriesActiveSeriesReached() public {
        uint256 SERIES_TO_INIT = 5;
        user1.doApprove(address(divider));
        user1.doMint(address(user1), SERIES_STAKE_AMOUNT * SERIES_TO_INIT);
        uint256 activeSeries = divider.activeSeries(address(feed));

        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
            uint256 nextMonthDate = DateLib.addMonths(block.timestamp, i);
            nextMonthDate = getValidMaturity(DateLib.getYear(nextMonthDate), DateLib.getMonth(nextMonthDate));
            assertTrue(DateLib.getMonth(nextMonthDate) == 10);
            assertTrue(DateLib.getYear(nextMonthDate) == 2021);
            assertTrue(DateLib.getDay(nextMonthDate) == 1);
            (address zero, address claim) = initSampleSeries(nextMonthDate);
            assertTrue(zero != address(0));
            assertTrue(claim != address(0));
        }
        assertTrue(divider.activeSeries(address(feed)) == activeSeries + SERIES_TO_INIT);
    }

    //    function testFailInitSeriesMoreThan3Months() public {
    //    }

    //    function testFailInitSeriesIfEmergencyStop() public {}

    function testInitSeries() public {
        uint256 activeSeries = divider.activeSeries(address(feed));
        uint256 maturity = getValidMaturity(2021, 10);
        (address zero, address claim) = initSampleSeries(maturity);
        assertTrue(divider.activeSeries(address(feed)) == activeSeries + 1);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
    }

    //    function testInitThreeSeries() public {
    //        uint256 SERIES_TO_INIT = 3;
    //        user1.doApprove(address(divider));
    //        user1.doMint(address(user1), SERIES_STAKE_AMOUNT * SERIES_TO_INIT);
    //        uint256 activeSeries = divider.activeSeries(address(feed));
    //
    //        for (uint256 i = 1; i <= SERIES_TO_INIT; i++) {
    //            uint256 nextMonthDate = DateLib.addMonths(block.timestamp, i);
    //            nextMonthDate = getValidMaturity(DateLib.getYear(nextMonthDate), DateLib.getMonth(nextMonthDate));
    //            assertTrue(DateLib.getMonth(nextMonthDate) == 10);
    //            assertTrue(DateLib.getYear(nextMonthDate) == 2021);
    //            assertTrue(DateLib.getDay(nextMonthDate) == 1);
    //            (address zero, address claim) = initSampleSeries(nextMonthDate);
    //            assertTrue(zero != address(0));
    //            assertTrue(claim != address(0));
    //        }
    ////        assertTrue(divider.activeSeries(address(feed)) == activeSeries + SERIES_TO_INIT);
    //    }

    // settleSeries() tests
    //    function testFailSettleSeriesAlreadySettled() public {}
    //    function testFailSettleSeriesIfNotSponsorAndSponsorWindow() public {}
    //    function testFailSettleSeriesCutoffTime() public {}
    //    function testFailSettleSeriesIfCutoffTime() public {}
    //    function testFailSettleSeriesIfSponsorAndCutoffTime() public {}
    //    function testFailSettleSeriesIfNotSponsorAndSponsorTime() public {}
    //
    function testSettleSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        // 01-10-2021
        (address zero, address claim) = initSampleSeries(maturity);
        hevm.warp(maturity);
        user1.doSettleSeries(address(feed), maturity);
    }

    //    function testSettleSeriesIfSponsorAndSponsorWindow() public {}
    //    function testSettleSeriesIfNotSponsorAndSettlementWindow() public {}
    //
    //    function testSettleSeriesAndRewardTransferred() public {}

    // issue() tests
    //    function testFailIssueFeedDisabled() public {}
    //    function testFailIssueSeriesNotExists() public {}
    //    function testFailIssueNotEnoughBalance() public {}
    //
    //    function testIssue() public {}

    // combine() tests
    //    function testCombine() public {}

    // redeemZero() tests
    //    function testRedeemZero() public {}

    // collect() tests
    //    function testFailCollectIfNotClaimContract() public {}
    //    function testCollect() public {}

    // emergency tests

    // -- test helpers --
    function getValidMaturity(uint256 year, uint256 month) public returns (uint256 maturity) {
        uint256 maturityDay = 1;
        maturity = DateLib.timestampFromDate(year, month, 1);
        require(maturity >= block.timestamp + 2 weeks, "Can not return valid maturity with given year an month");
    }

    function initSampleSeries(uint256 maturity) public returns (address zero, address claim) {
        user1.doApprove(address(divider));
        user1.doMint(address(user1), SERIES_STAKE_AMOUNT);
        (zero, claim) = user1.doInitSeries(address(feed), maturity);
    }
}
