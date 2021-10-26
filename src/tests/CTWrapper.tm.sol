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

    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

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
        ctwrapper.initialize(COMP, address(this), COMP);
        ctwrapper.join(address(this), 100e18);
        ctwrapper.exit(address(this), 100e18);
    }
}
