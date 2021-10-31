// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockFeed } from "./test-helpers/mocks/MockFeed.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { IFeed } from "./test-helpers/interfaces/IFeed.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { BaseFeed } from "../feeds/BaseFeed.sol";
import { Errors } from "../libs/Errors.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        MockFeed feedImpl = new MockFeed();
        MockFactory someFactory = new MockFactory(
            address(feedImpl),
            address(twImpl),
            address(divider),
            DELTA,
            address(reward),
            address(stake),
            ISSUANCE_FEE,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY
        );
        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).feedImpl(), address(feedImpl));
        assertEq(MockFactory(someFactory).twImpl(), address(twImpl));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        assertEq(MockFactory(someFactory).delta(), DELTA);
        assertEq(MockFactory(someFactory).reward(), address(reward));
        assertEq(MockFactory(someFactory).stake(), address(stake));
        assertEq(MockFactory(someFactory).issuanceFee(), ISSUANCE_FEE);
        assertEq(MockFactory(someFactory).stakeSize(), STAKE_SIZE);
        assertEq(MockFactory(someFactory).minMaturity(), MIN_MATURITY);
        assertEq(MockFactory(someFactory).maxMaturity(), MAX_MATURITY);
    }

    function testDeployFeed() public {
        uint256 issuanceFee = 0.01e18;
        uint256 _stakeSize = 1e18;
        uint256 minMaturity = 2 weeks;
        uint256 maxMaturity = 14 weeks;
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        address feed = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        (address target, uint256 delta, uint256 ifee, address stake, uint256 stakeSize, uint256 minm, uint256 maxm) = BaseFeed(feed).feedParams();
        assertEq(IFeed(feed).divider(), address(divider));
        assertEq(target, address(someTarget));
        assertEq(delta, DELTA);
        assertEq(IFeed(feed).name(), "Some Target Feed");
        assertEq(IFeed(feed).symbol(), "ST-feed");
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
    }

    function testDeployFeedAndinitializeSeries() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        (address f, address wt) = periphery.onboardFeed(address(someFactory), address(someTarget));
        assertTrue(f != address(0));
        uint256 scale = IFeed(f).scale();
        assertEq(scale, 1e17);
        hevm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        (address zero, address claim) = alice.doSponsorSeries(f, maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
    }

    function testCantDeployFeedIfTargetIsNotSupported() public {
        MockToken newTarget = new MockToken("Not Supported", "NS", 18);
        try factory.deployFeed(address(newTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
    }

    function testCantDeployFeedIfTargetIsNotSupportedOnSpecificFeed() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        try factory.deployFeed(address(someTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
        someFactory.deployFeed(address(someTarget));
    }

    function testCantDeployFeedIfAlreadyExists() public {
        try factory.deployFeed(address(target)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.FeedAlreadyExists);
        }
    }
}
