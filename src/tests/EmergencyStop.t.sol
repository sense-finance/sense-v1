// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Errors } from "../libs/Errors.sol";
import { EmergencyStop } from "../utils/EmergencyStop.sol";

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";

contract Emergency is TestHelper {
    function testAllAdaptersAreStopped() public {
        address[] memory adapters = new address[](11);
        address[] memory targets = new address[](11);
        targets[0] = address(target);
        adapters[0] = address(adapter);
        for (uint256 i = 1; i <= 10; i++) {
            MockToken target = new MockToken("Test Target", "TT", 18);
            factory.addTarget(address(target), true);
            address adapter = factory.deployAdapter(address(target));
            targets[i] = address(target);
            adapters[i] = address(adapter);
        }
        EmergencyStop e = new EmergencyStop(address(divider));
        divider.setIsTrusted(address(e), true);
        e.stop(adapters);

        assert(divider.permissionless() == false);
        for (uint256 i = 0; i < adapters.length; i++) {
            assert(divider.adapters(adapters[i]) == false);
        }
    }

    function testCantStopAdaptersIfNotAuthorized() public {
        address[] memory adapters = new address[](11);
        address[] memory targets = new address[](11);
        targets[0] = address(target);
        adapters[0] = address(adapter);
        for (uint256 i = 1; i <= 10; i++) {
            MockToken target = new MockToken("Test Target", "TT", 18);
            factory.addTarget(address(target), true);
            address adapter = factory.deployAdapter(address(target));
            targets[i] = address(target);
            adapters[i] = address(adapter);
        }
        EmergencyStop e = new EmergencyStop(address(divider));
        try e.stop(adapters) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }
}
