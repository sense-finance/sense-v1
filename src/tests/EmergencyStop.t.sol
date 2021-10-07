// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Errors } from "../libs/Errors.sol";
import { EmergencyStop } from "../feeds/EmergencyStop.sol";

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/MockToken.sol";

contract Emergency is TestHelper {
    function testAllFeedsAreStopped() public {
        address[] memory feeds = new address[](11);
        address[] memory targets = new address[](11);
        targets[0] = address(target);
        feeds[0] = address(feed);
        for (uint256 i = 1; i <= 10; i++) {
            MockToken target = new MockToken("Test Target", "TT");
            factory.addTarget(address(target), true);
            address feed = factory.deployFeed(address(target));
            targets[i] = address(target);
            feeds[i] = address(feed);
        }
        EmergencyStop e = new EmergencyStop(address(divider));
        divider.setIsTrusted(address(e), true);
        e.stop(feeds);

        for (uint256 i = 0; i < feeds.length; i++) {
            assert(divider.feeds(feeds[i]) == false);
        }
    }

    function testCantStopFeedsIfNotAuthorized() public {
        address[] memory feeds = new address[](11);
        address[] memory targets = new address[](11);
        targets[0] = address(target);
        feeds[0] = address(feed);
        for (uint256 i = 1; i <= 10; i++) {
            MockToken target = new MockToken("Test Target", "TT");
            factory.addTarget(address(target), true);
            address feed = factory.deployFeed(address(target));
            targets[i] = address(target);
            feeds[i] = address(feed);
        }
        EmergencyStop e = new EmergencyStop(address(divider));
        try e.stop(feeds) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }
}
