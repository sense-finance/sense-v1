// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "./test-helpers/MockFeed.sol";
import "./test-helpers/MockToken.sol";
import "./test-helpers/TestHelper.sol";

contract FakeFeed is BaseFeed {
    function _scale() internal virtual override returns (uint256 _value) {
        _value = 100e18;
    }

    function doSetFeed(Divider d, address _feed) public {
        d.setFeed(_feed, true);
    }
}

contract Feeds is TestHelper {
    using WadMath for uint256;

    function testFeedHasParams() public {
        MockToken target = new MockToken("Compound Dai", "cDAI");
        MockFeed feed = new MockFeed(GROWTH_PER_SECOND);
        feed.initialize(address(target), address(divider), DELTA);

        assertEq(feed.target(), address(target));
        assertEq(feed.divider(), address(divider));
        assertEq(feed.delta(), DELTA);
        assertEq(feed.name(), "Compound Dai Yield");
        assertEq(feed.symbol(), "cDAI-yield");
    }

    function testScale() public {
        assertEq(feed.scale(), feed.INITIAL_VALUE());
    }

    function testScaleIfEqualDelta() public {
        uint256[] memory startingScales = new uint256[](4);
        startingScales[0] = 2e20; // 200 WAD
        startingScales[1] = 1e18; // 1 WAD
        startingScales[2] = 1e17; // 0.1 WAD
        startingScales[3] = 4e15; // 0.004 WAD
        for (uint256 i = 0; i < startingScales.length; i++) {
            MockFeed localFeed = new MockFeed(GROWTH_PER_SECOND);
            localFeed.initialize(address(target), address(divider), DELTA);
            uint256 startingScale = startingScales[i];

            hevm.warp(0);
            localFeed.setScale(startingScale);
            // Set starting scale and store it as lscale
            localFeed.scale();
            (uint256 ltimestamp, uint256 lvalue) = localFeed.lscale();
            assertEq(lvalue, startingScale);

            hevm.warp(1 days);

            // 86400 (1 day)
            uint256 timeDiff = block.timestamp - ltimestamp;
            // Find the scale value would bring us right up to the acceptable growth per second (delta)?
            // Equation rationale:
            //      *  DELTA is the max tolerable percent growth in the scale value per second.
            //      *  So, we multiply that by the number of seconds that have passed.
            //      *  And multiply that result by the previous scale value to
            //         get the max amount of scale that we say can have grown.
            //         We are functionally doing `maxPercentIncrease * value`, which gets
            //         us the max *amount* that the value could have increased by.
            //      *  Then add that max increase to the original value to get the maximum possible.
            uint256 maxScale = (DELTA * timeDiff).wmul(lvalue) + lvalue;

            // Set max scale and ensure calling `scale` with it doesn't revert
            localFeed.setScale(maxScale);
            localFeed.scale();

            // add 1 more day
            hevm.warp(2 days);
            (ltimestamp, lvalue) = localFeed.lscale();
            timeDiff = block.timestamp - ltimestamp;
            maxScale = (DELTA * timeDiff).wmul(lvalue) + lvalue;
            localFeed.setScale(maxScale);
            localFeed.scale();
        }
    }

    function testCantScaleIfMoreThanDelta() public {
        uint256[] memory startingScales = new uint256[](4);
        startingScales[0] = 2e20; // 200 WAD
        startingScales[1] = 1e18; // 1 WAD
        startingScales[2] = 1e17; // 0.1 WAD
        startingScales[3] = 4e15; // 0.004 WAD
        for (uint256 i = 0; i < startingScales.length; i++) {
            MockFeed localFeed = new MockFeed(GROWTH_PER_SECOND);
            localFeed.initialize(address(target), address(divider), DELTA);
            uint256 startingScale = startingScales[i];

            hevm.warp(0);
            localFeed.setScale(startingScale);
            // Set starting scale and store it as lscale
            localFeed.scale();
            (uint256 ltimestamp, uint256 lvalue) = localFeed.lscale();
            assertEq(lvalue, startingScale);

            hevm.warp(1 days);

            // 86400 (1 day)
            uint256 timeDiff = block.timestamp - ltimestamp;
            // find the scale value would bring us right up to the acceptable growth per second (delta)?
            uint256 maxScale = (DELTA * timeDiff).wmul(lvalue) + lvalue;

            // `maxScale * 1.000001` (adding small numbers wasn't enough to trigger the delta check as they got rounded
            // away in wdivs)
            localFeed.setScale(maxScale.wmul(1000001e12));

            try localFeed.scale() {
                fail();
            } catch Error(string memory error) {
                assertEq(error, Errors.InvalidScaleValue);
            }
        }
    }

    function testCantScaleIfBelowPrevious() public {
        assertEq(feed.scale(), feed.INITIAL_VALUE());
        feed.setScale(feed.INITIAL_VALUE() - 1);
        try feed.scale() {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.InvalidScaleValue);
        }
    }

    function testCantAddCustomFeedToDivider() public {
        MockToken newTarget = new MockToken("Compound USDC", "cUSDC");
        controller.supportTarget(address(newTarget), true);
        FakeFeed fakeFeed = new FakeFeed();
        fakeFeed.initialize(address(newTarget), address(divider), 0);
        try fakeFeed.doSetFeed(divider, address(fakeFeed)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }
}
