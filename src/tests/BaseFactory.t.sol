// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockFeed } from "./test-helpers/mocks/MockFeed.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTWrapper } from "./test-helpers/mocks/MockTWrapper.sol";
import { IFeed } from "./test-helpers/interfaces/IFeed.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { Errors } from "../libs/errors.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        MockFeed feedImpl = new MockFeed();
        MockTWrapper twImpl = new MockTWrapper();
        MockFactory someFactory = new MockFactory(
            address(feedImpl),
            address(twImpl),
            address(divider),
            DELTA,
            address(1)
        );
        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).feedImpl(), address(feedImpl));
        assertEq(MockFactory(someFactory).twImpl(), address(twImpl));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        assertEq(MockFactory(someFactory).delta(), DELTA);
        assertEq(MockFactory(someFactory).reward(), address(1));
    }

    function testDeployFeed() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        (address feed, address tWrapper) = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        assertTrue(tWrapper != address(0));
        assertEq(IFeed(feed).target(), address(someTarget));
        assertEq(IFeed(feed).divider(), address(divider));
        assertEq(IFeed(feed).delta(), DELTA);
        assertEq(IFeed(feed).name(), "Some Target Yield");
        assertEq(IFeed(feed).symbol(), "ST-yield");
        assertEq(IFeed(feed).symbol(), "ST-yield");
        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
    }

    function testDeployFeedAndinitializeSeries() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        (address feed, ) = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
        hevm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        (address zero, address claim) = alice.doSponsorSeries(feed, maturity);
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
