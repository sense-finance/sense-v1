// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/feed/FeedTest.sol";
import "./test-helpers/feed/MockFeed.sol";
import "./test-helpers/MockToken.sol";

contract Feeds is FeedTest {
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
        assertEq(feed.scale(), DELTA);
    }

    function testScaleIfEqualDelta() public {
        feed.scale();
        (uint256 ltimestamp, uint256 lvalue) = feed.lscale();
        hevm.warp(block.timestamp + 1 days);
        uint256 timeDiff = block.timestamp - ltimestamp;
//        uint256 maxGrowth = DELTA * timeDiff;
//        uint256 growthPerSec = _value.div(lvalue).div(timeDiff);

        uint256 maxGrowth = DELTA * timeDiff * lvalue;
//        uint256 maxGrowth = GROWTH_PER_SECOND * timeDiff;
        feed.setScale(maxGrowth);
        feed.scale();
        assertEq(maxGrowth, feed.delta());
        assertEq(timeDiff, ltimestamp);
    }

    function testCantScaleIfMoreThanDelta() public {
        feed.scale();
        (uint256 ltimestamp, uint256 lvalue) = feed.lscale();
        hevm.warp(block.timestamp + 1 days);
        uint256 timeDiff = block.timestamp - ltimestamp;
        //        uint256 maxGrowth = DELTA * timeDiff;
        //        uint256 growthPerSec = _value.div(lvalue).div(timeDiff);

        uint256 maxGrowth = DELTA * timeDiff * lvalue;
        //        uint256 maxGrowth = GROWTH_PER_SECOND * timeDiff;
        feed.setScale(maxGrowth + 1); // we set the max growth +

        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
        assertEq(maxGrowth, feed.delta());
        assertEq(timeDiff, ltimestamp);
    }

    function testCantScaleIfBelowThanPrevious() public {
        assertEq(feed.scale(), GROWTH_PER_SECOND);
        feed.setScale(GROWTH_PER_SECOND - 1);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }
}
