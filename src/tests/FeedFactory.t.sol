// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/TestHelper.sol";
import "./test-helpers/interfaces/IFeed.sol";

contract FactoryTester is TestHelper {
    function testDeployFeed() public {
        address feed = factory.deployFeed(address(target));
        assertTrue(feed != address(0));
        assertEq(IFeed(feed).target(), address(target));
        assertEq(IFeed(feed).divider(), address(divider));
        assertEq(IFeed(feed).delta(), DELTA);
        assertEq(IFeed(feed).name(), "Compound Dai Yield");
        assertEq(IFeed(feed).symbol(), "cDAI-yield");

        uint256 scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
    }

    function testDeployFeedAndInitialiseSeries() public {
        address feed = factory.deployFeed(address(target));
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
}
