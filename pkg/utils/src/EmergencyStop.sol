// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { Divider } from "@sense-finance/v1-core/Divider.sol";

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
