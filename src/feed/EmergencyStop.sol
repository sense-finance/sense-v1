// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
import "../Divider.sol";

// @title Stops all feeds from the divider
contract EmergencyStop is Warded {
    address public divider;

    constructor(address _divider) Warded() {
        divider = _divider;
    }

    function stop(address[] memory feeds) external virtual onlyWards {
        for (uint256 i = 0; i < feeds.length; i++) {
            Divider(divider).setFeed(feeds[i], false);
            emit Stopped(feeds[i]);
        }
    }

    event Stopped(address indexed feed);
}
