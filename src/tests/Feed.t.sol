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

    function testScaleIfEqualToDelta() public {
        hevm.roll(1);
        uint256 scale = feed.scale();
        uint256 delta = feed.delta();
        uint256 newValue = scale + (scale * delta) / 100;
        feed.setScale(newValue);
        feed.scale();
    }

    function testCantScaleIfBelowThanPrevious() public {
        hevm.roll(1);
        assertEq(feed.scale(), 1e17);
        feed.setScale(1e17 - 1);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }

    function testCantScaleIfMoreThanDelta() public {
        hevm.roll(1);
        uint256 scale = feed.scale();
        uint256 delta = feed.delta();
        uint256 newValue = scale + (scale * delta) / 100 + 1;
        feed.setScale(newValue);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }
}
