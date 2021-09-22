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

    MockFeed feed;
    MockToken stable;
    MockToken target;

    Divider internal divider;
    User internal alice;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        stable = new MockToken("Stable Token", "ST");
        target = new MockToken("Compound Dai", "cDAI");
        divider = new Divider(address(stable), address(this));

        feed = new MockFeed(address(target), address(divider), 150);
        divider.setFeed(address(feed), true);
    }
}
