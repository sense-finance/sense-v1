// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/feed/FeedTest.sol";
import "./test-helpers/feed/MockFeed.sol";
import "./test-helpers/MockToken.sol";

contract Feeds is FeedTest {
    function testFeedHasParams() public {
        MockToken target = new MockToken("Compound Dai", "cDAI");
        MockFeed feed = new MockFeed(address(target), address(divider), 150);

        assertEq(feed.target(), address(target));
        assertEq(feed.divider(), address(divider));
        assertEq(feed.delta(), 150);
        assertEq(feed.name(), "Compound Dai Yield");
        assertEq(feed.symbol(), "cDAI-yield");
    }

    function testScale() public {
        hevm.roll(block.number + 1);
        assertEq(feed.scale(), 1e17);
    }

    function testCantScaleIfMoreThanDelta() public {
        hevm.roll(block.number + 1);
        uint256 lscale = feed.scale();
        uint256 ltimestamp = block.timestamp;
        uint256 lscalePerSec = lscale / ltimestamp; // last scale value per second

        hevm.roll(block.number + 1);
        uint256 timeDiff = block.timestamp - ltimestamp;
        uint256 scaleAfterTime = lscalePerSec * timeDiff;
        uint256 maxScaleValue = scaleAfterTime + (scaleAfterTime * feed.delta()) / 100; // TODO double check
        feed.setScale(maxScaleValue);
        feed.scale();
    }

    function testCantScaleIfBelowThanPrevious() public {
        hevm.roll(block.number + 1);
        assertEq(feed.scale(), 1e17);
        feed.setScale(1e17 - 1);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }
}
