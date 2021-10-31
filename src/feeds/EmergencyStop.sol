// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Divider } from "../Divider.sol";

/// @notice Unsets multiple feeds on the divider
contract EmergencyStop is Trust {
    address public divider;

    constructor(address _divider) Trust(msg.sender) {
        divider = _divider;
    }

    function stop(address[] memory feeds) external virtual requiresTrust {
        Divider(divider).setPermissionless(false);
        for (uint256 i = 0; i < feeds.length; i++) {
            Divider(divider).setFeed(feeds[i], false);
            emit Stopped(feeds[i]);
        }
    }

    event Stopped(address indexed feed);
}
