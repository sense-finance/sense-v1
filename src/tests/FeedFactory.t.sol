// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/TestHelper.sol";
import "./test-helpers/interfaces/IFeed.sol";

contract FactoryTester is TestHelper {
    function testDeployFeed() public {
        hevm.roll(block.number + 1);
        address feed = factory.deployFeed(address(target));
        assertTrue(feed != address(0));
        assertEq(IFeed(feed).target(), address(target));
        assertEq(IFeed(feed).divider(), address(divider));
        assertEq(IFeed(feed).delta(), 150);
        assertEq(IFeed(feed).name(), "Compound Dai Yield");
        assertEq(IFeed(feed).symbol(), "cDAI-yield");

        uint256 scale = IFeed(feed).scale();
        scale = IFeed(feed).scale();
        assertEq(scale, 1e17);
    }

    function testDeployFeedAndInitialiseSeries() public {
        hevm.roll(block.number + 1);
        address feed = factory.deployFeed(address(target));
        assertTrue(feed != address(0));
        uint256 scale = IFeed(feed).scale();
        scale = IFeed(feed).scale();
        assertEq(scale, 1e17);

        hevm.warp(1630454400); // 01/09/2021
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);

        (address zero, address claim) = alice.doInitSeries(feed, maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
    }

    function testCantDeployFeedIfTargetIsNotSupported() public {
        hevm.roll(block.number + 1);
        MockToken newTarget = new MockToken("Not Supported", "NS");
        try factory.deployFeed(address(newTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
    }
}
