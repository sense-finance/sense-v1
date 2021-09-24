// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/feed/FeedTest.sol";
import "./test-helpers/feed/MockFeed.sol";
import "./test-helpers/MockToken.sol";

contract Feeds is FeedTest {
    uint256 constant public WAD = 1e18;

    using WadMath for uint256;

    function testFeedHasParams() public {
        MockToken target = new MockToken("Compound Dai", "cDAI");
        MockFeed feed = new MockFeed(address(target), address(divider), 150, 150);

        assertEq(feed.target(), address(target));
        assertEq(feed.divider(), address(divider));
        assertEq(feed.delta(), 150);
        assertEq(feed.name(), "Compound Dai Yield");
        assertEq(feed.symbol(), "cDAI-yield");
    }

    function testScale() public {
        hevm.roll(block.number + 1);
        assertEq(feed.scale(), WAD);
    }

    function testScaleIfEqualDelta() public {
        hevm.warp(0);
        feed.scale();
        // Initializes to ltimestamp = 0 & lvalue = 1 WAD
        (uint256 ltimestamp, uint256 lvalue) = feed.lscale();

        hevm.warp(1 days);

        // 86400 (1 day)
        uint256 timeDiff = block.timestamp - ltimestamp;

        // What scale value would bring us right up to the acceptable growth per second (delta)?
        uint256 maxScale = (DELTA * timeDiff + lvalue).wdiv(lvalue);

        feed.setScale(maxScale);
        feed.scale();

        // Logging
        // assertTrue(false);
    }

    function testCantScaleIfMoreThanDelta() public {
        hevm.warp(0);
        feed.scale();
        (uint256 ltimestamp, uint256 lvalue) = feed.lscale();

        hevm.warp(1 days);
        uint256 timeDiff = block.timestamp - ltimestamp;
        uint256 maxScale = (DELTA * timeDiff + lvalue).wdiv(lvalue);

        // `maxScale * 1.000001` (adding small numbers wasn't enough to trigger the delta check as they got rounded away in wdivs)
        feed.setScale(maxScale.wmul(1000001e12));

        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }

    function testCantScaleIfBelowThanPrevious() public {
        assertEq(feed.scale(), WAD);
        feed.setScale(WAD - 1);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }
}
