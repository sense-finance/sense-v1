// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/TestHelper.sol";
import "./test-helpers/interfaces/IFeed.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        MockFeed implementation = new MockFeed(GROWTH_PER_SECOND);
        MockFactory someFactory = new MockFactory(address(implementation), address(divider), DELTA);
        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).implementation(), address(implementation));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        assertEq(MockFactory(someFactory).delta(), DELTA);
    }

    function testDeployFeed() public {
        MockToken someTarget = new MockToken("Some Target", "ST");
        MockFactory someFactory = createFactory(address(someTarget));
        address feed = someFactory.deployFeed(address(someTarget));
        assertTrue(feed != address(0));
        assertEq(IFeed(feed).target(), address(someTarget));
        assertEq(IFeed(feed).divider(), address(divider));
        assertEq(IFeed(feed).delta(), DELTA);
        assertEq(IFeed(feed).name(), "Some Target Yield");
        assertEq(IFeed(feed).symbol(), "ST-yield");
        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
    }

    function testDeployFeedAndInitialiseSeries() public {
        MockToken someTarget = new MockToken("Some Target", "ST");
        MockFactory someFactory = createFactory(address(someTarget));
        address feed = someFactory.deployFeed(address(someTarget));
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
        MockToken newTarget = new MockToken("Not Supported", "NS");
        try factory.deployFeed(address(newTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
    }

    function testCantDeployFeedIfTargetIsNotSupportedOnSpecificFeed() public {
        MockToken someTarget = new MockToken("Some Target", "ST");
        MockFactory someFactory = createFactory(address(someTarget));
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
