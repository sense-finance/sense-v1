// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "ds-test/test.sol";

// internal references
import "../feed/compound/CFeed.sol";
import "./test-helpers/MockFactory.sol";
import "./test-helpers/Hevm.sol";
import "./test-helpers/DateTimeFull.sol";
import "./test-helpers/User.sol";

contract CFeedTestHelper is DSTest {
    CFeed feed;
    MockFactory internal factory;
    Divider internal divider;

    uint256 public constant DELTA = 150;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    function setUp() public {
        divider = new Divider(DAI, address(this));
        CFeed implementation = new CFeed(); // compound feed implementation
        // deploy compound feed factory
        factory = new MockFactory(address(implementation), address(divider), DELTA);
        factory.addTarget(cDAI, true);
        divider.rely(address(factory)); // add factory as a ward
        feed = CFeed(factory.deployFeed(cDAI)); // deploy a cDAI feed
    }
}

contract CFeeds is CFeedTestHelper {
    using WadMath for uint256;

    function testCFeedScale() public {
        CTokenInterface underlying = CTokenInterface(DAI);
        CTokenInterface ctoken = CTokenInterface(cDAI);

        uint256 decimals = 1 * 10**(18 - 8 + underlying.decimals());
        uint256 scale = ctoken.exchangeRateCurrent().wdiv(decimals);
        assertEq(feed.scale(), scale);
    }
}
