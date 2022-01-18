// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Divider } from "@sense-finance/v1-core/src/Divider.sol";

/// @notice Unsets multiple adapters on the divider
contract EmergencyStop is Trust {
    address public immutable divider;

    constructor(address _divider) Trust(msg.sender) {
        divider = _divider;
    }

    function stop(address[] memory adapters) external virtual requiresTrust {
        Divider(divider).setPermissionless(false);
        for (uint256 i = 0; i < adapters.length; i++) {
            Divider(divider).setAdapter(adapters[i], false);
            emit Stopped(adapters[i]);
        }
    }

    event Stopped(address indexed adapter);
}
