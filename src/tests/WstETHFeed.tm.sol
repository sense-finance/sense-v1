// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, AssetDeployer } from "../Divider.sol";
import { WstETHFeed, WstETHInterface } from "../feeds/lido/WstETHFeed.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract WstETHFeedTestHelper is DSTest {
    WstETHFeed feed;
    MockFactory internal factory;
    Divider internal divider;
    AssetDeployer internal assetDeployer;

    uint256 public constant DELTA = 150;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    function setUp() public {
        assetDeployer = new AssetDeployer();
        divider = new Divider(DAI, address(this), address(assetDeployer));
        assetDeployer.init(address(divider));
        WstETHFeed feedImpl = new WstETHFeed(); // wstETH feed implementation
        // deploy wstETH feed factory
        factory = new MockFactory(address(feedImpl), address(0), address(divider), DELTA, DAI);
        // TODO replace for a real reward token
        factory.addTarget(wstETH, true);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        (address f, ) = factory.deployFeed(wstETH);
        feed = WstETHFeed(f); // deploy a wstETH feed
    }
}

contract WstETHFeeds is WstETHFeedTestHelper {
    using FixedMath for uint256;

    function testWstETHFeedScale() public {
        WstETHInterface wstETH = WstETHInterface(wstETH);

        uint256 scale = wstETH.stEthPerToken();
        assertEq(feed.scale(), scale);
    }
}
