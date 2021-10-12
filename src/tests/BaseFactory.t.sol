// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockFeed } from "./test-helpers/MockFeed.sol";
import { MockFactory } from "./test-helpers/MockFactory.sol";
import { MockToken } from "./test-helpers/MockToken.sol";
import { IFeed } from "./test-helpers/interfaces/IFeed.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { Errors } from "../libs/errors.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        MockFeed implementation = new MockFeed();
        MockFactory someFactory = new MockFactory(address(implementation), address(divider), DELTA, address(1));
        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).implementation(), address(implementation));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        assertEq(MockFactory(someFactory).delta(), DELTA);
        assertEq(MockFactory(someFactory).airdropToken(), address(1));
    }

    function testDeployFeed() public {
        MockToken someAirdrop = new MockToken("Some Airdrop", "SA", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someAirdrop));
        (address feed, address wTarget) = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        assertTrue(wTarget != address(0));
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
        MockToken someAirdrop = new MockToken("Some Airdrop", "SA", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someAirdrop));
        (address feed, ) = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
        hevm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        (address zero, address claim) = alice.doInitSeries(feed, maturity);
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
        MockToken someAirdrop = new MockToken("Some Airdrop", "SA", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someAirdrop));
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
