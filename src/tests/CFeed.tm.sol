// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, AssetDeployer } from "../Divider.sol";
import { CFeed, CTokenInterface } from "../feeds/compound/CFeed.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CFeedTestHelper is DSTest {
    CFeed feed;
    MockFactory internal factory;
    Divider internal divider;
    AssetDeployer internal assetDeployer;

    uint256 public constant DELTA = 150;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    function setUp() public {
        assetDeployer = new AssetDeployer();
        divider = new Divider(DAI, address(this), address(assetDeployer));
        assetDeployer.init(address(divider));
        CFeed feedImpl = new CFeed(); // compound feed implementation
        // deploy compound feed factory
        factory = new MockFactory(address(feedImpl), address(0), address(divider), DELTA, DAI);
        // TODO replace for a real reward token
        factory.addTarget(cDAI, true);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        (address f, ) = factory.deployFeed(cDAI);
        feed = CFeed(f); // deploy a cDAI feed
    }
}

contract CFeeds is CFeedTestHelper {
    using FixedMath for uint256;

    function testCFeedScale() public {
        CTokenInterface underlying = CTokenInterface(DAI);
        CTokenInterface ctoken = CTokenInterface(cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent().fdiv(10**(18 - 8 + uDecimals), 10**uDecimals);
        assertEq(feed.scale(), scale);
    }
}
