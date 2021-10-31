// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Periphery } from "../Periphery.sol";
import { GClaimManager } from "../modules/GClaimManager.sol";
import { CFeed, CTokenInterface } from "../feeds/compound/CFeed.sol";
import { CTWrapper, ComptrollerInterface } from "../wrappers/compound/CTWrapper.sol";
import { CFactory } from "../feeds/compound/CFactory.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract CTWrapperTestHelper is DSTest {
    CTWrapper internal ctwrapper;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    function setUp() public {
        CFeed feed = new CFeed(); // compound feed implementation
        ctwrapper = new CTWrapper(); // compound target wrapper implementation
    }
}

contract CTWrappers is CTWrapperTestHelper {
    using FixedMath for uint256;

    // TODO: this is only checking the flow, we should write proper tests against mainnet using an address
    // that we know that will receive some COMP when calling the claim function
    function testClaimReward() public {
        ctwrapper.initialize(address(this), cDAI, DAI, COMP);
        ctwrapper.join(address(this), 100e18);
        ctwrapper.exit(address(this), 100e18);
    }
}
