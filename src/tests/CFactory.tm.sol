// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CFeed } from "../feeds/compound/CFeed.sol";
import { CFactory } from "../feeds/compound/CFactory.sol";
import { Divider } from "../Divider.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

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
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract CFactories is CFeedTestHelper {
    function testDeployFactory() public {
        CFeed implementation = new CFeed();
        CFactory otherCFactory = new CFactory(address(implementation), address(divider), DELTA);
        // TODO: replace for a real one
        assertTrue(address(otherCFactory) != address(0));
        assertEq(CFactory(otherCFactory).implementation(), address(implementation));
        assertEq(CFactory(otherCFactory).divider(), address(divider));
        assertEq(CFactory(otherCFactory).delta(), DELTA);
    }

    function testDeployFeed() public {
        address f = factory.deployFeed(cDAI);
        CFeed feed = CFeed(f);
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
