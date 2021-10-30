// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, AssetDeployer } from "../Divider.sol";
import { CFeed, CTokenInterface } from "../feeds/compound/CFeed.sol";
import { CFactory } from "../feeds/compound/CFactory.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CFeedTestHelper is DSTest {
    CFeed feed;
    CFactory internal factory;
    Divider internal divider;
    AssetDeployer internal assetDeployer;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant INIT_STAKE = 1e18;
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
            INIT_STAKE,
            MIN_MATURITY,
            MAX_MATURITY
        );
        //        factory.addTarget(cDAI, true);
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
