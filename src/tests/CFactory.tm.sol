// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "ds-test/test.sol";

// internal references
import "../feed/compound/CFeed.sol";
import "../feed/compound/CFactory.sol";

import "./test-helpers/Hevm.sol";
import "./test-helpers/DateTimeFull.sol";
import "./test-helpers/User.sol";

contract CFeedTestHelper is DSTest {
    CFactory internal factory;
    Divider internal divider;

    uint256 public constant DELTA = 150;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    function setUp() public {
        divider = new Divider(DAI, address(this));
        CFeed implementation = new CFeed(); // compound feed implementation
        // deploy compound feed factory
        factory = new CFactory(address(implementation), address(divider), DELTA);
        divider.rely(address(factory)); // add factory as a ward
    }
}

contract CFactories is CFeedTestHelper {
    function testDeployFactory() public {
        CFeed implementation = new CFeed();
        CFactory otherCFactory = new CFactory(address(implementation), address(divider), DELTA);
        assertTrue(address(otherCFactory) != address(0));
        assertEq(CFactory(otherCFactory).implementation(), address(implementation));
        assertEq(CFactory(otherCFactory).divider(), address(divider));
        assertEq(CFactory(otherCFactory).delta(), DELTA);
    }

    function testDeployFeed() public {
        CFeed feed = CFeed(factory.deployFeed(cDAI));
        assertTrue(address(feed) != address(0));
        assertEq(CFeed(feed).target(), address(cDAI));
        assertEq(CFeed(feed).divider(), address(divider));
        assertEq(CFeed(feed).delta(), DELTA);
        assertEq(CFeed(feed).name(), "Compound Dai Yield");
        assertEq(CFeed(feed).symbol(), "cDAI-yield");

        uint256 scale = CFeed(feed).scale();
        assertTrue(scale > 0);
    }
}
