// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CFeed } from "../feeds/compound/CFeed.sol";
import { CFactory } from "../feeds/compound/CFactory.sol";
import { Divider, AssetDeployer } from "../Divider.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CFeedTestHelper is DSTest {
    CFactory internal factory;
    Divider internal divider;
    AssetDeployer internal assetDeployer;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        assetDeployer = new AssetDeployer();
        divider = new Divider(address(this), address(assetDeployer));
        assetDeployer.init(address(divider));
        CFeed feedImpl = new CFeed(); // compound feed implementation
        // deploy compound feed factory
        factory = new CFactory(
            address(feedImpl),
            address(0),
            address(divider),
            DELTA,
            COMP,
            DAI,
            ISSUANCE_FEE,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY
        );
        divider.setIsTrusted(address(factory), true); // add factory as a ward
    }
}

contract CFactories is CFeedTestHelper {
    function testDeployFactory() public {
        CFeed feedImpl = new CFeed();
        CFactory otherCFactory = new CFactory(
            address(feedImpl),
            address(0),
            address(divider),
            DELTA,
            COMP,
            DAI,
            ISSUANCE_FEE,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY
        );
        assertTrue(address(otherCFactory) != address(0));
        assertEq(CFactory(otherCFactory).feedImpl(), address(feedImpl));
        assertEq(CFactory(otherCFactory).divider(), address(divider));
        assertEq(CFactory(otherCFactory).delta(), DELTA);
        assertEq(CFactory(otherCFactory).reward(), COMP);
        assertEq(CFactory(otherCFactory).stake(), DAI);
        assertEq(CFactory(otherCFactory).issuanceFee(), ISSUANCE_FEE);
        assertEq(CFactory(otherCFactory).stakeSize(), STAKE_SIZE);
        assertEq(CFactory(otherCFactory).minMaturity(), MIN_MATURITY);
        assertEq(CFactory(otherCFactory).maxMaturity(), MAX_MATURITY);
    }

    function testDeployFeed() public {
        (address f, ) = factory.deployFeed(cDAI);
        CFeed feed = CFeed(f);
        assertTrue(address(feed) != address(0));
        assertEq(CFeed(feed).target(), address(cDAI));
        assertEq(CFeed(feed).divider(), address(divider));
        assertEq(CFeed(feed).delta(), DELTA);
        assertEq(CFeed(feed).name(), "Compound Dai Feed");
        assertEq(CFeed(feed).symbol(), "cDAI-feed");

        uint256 scale = CFeed(feed).scale();
        assertTrue(scale > 0);
    }
}
