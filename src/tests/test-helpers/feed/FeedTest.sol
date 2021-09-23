// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "ds-test/test.sol";

// Internal references
import "../MockToken.sol";
import "./MockFeed.sol";
import "../divider/User.sol";
import "../../../Divider.sol";
import "../Hevm.sol";

contract FeedTest is DSTest {
    using WadMath for uint256;

    MockFeed feed;
    MockToken stable;
    MockToken target;

    Divider internal divider;
    User internal alice;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);
    uint256 internal constant GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 internal constant DELTA = 800672247590; // GROWTH_PER_SECOND + 1% = 25.25% APY

    function setUp() public {
        hevm.warp(1630454400);
        // 01-09-21 00:00 UTC

        stable = new MockToken("Stable Token", "ST");
        target = new MockToken("Compound Dai", "cDAI");
        divider = new Divider(address(stable), address(this));

        feed = new MockFeed(address(target), address(divider), DELTA, GROWTH_PER_SECOND);
        divider.setFeed(address(feed), true);
    }
}
