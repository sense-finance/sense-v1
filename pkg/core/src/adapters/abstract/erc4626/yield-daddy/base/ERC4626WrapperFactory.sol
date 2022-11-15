// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { ERC4626Factory } from "@yield-daddy/src/base/ERC4626Factory.sol";

/// @title ERC4626WrapperFactory
/// @notice Adds restrictedAdmin and rewardsRecipient to ERC4626Factory from yield-daddy
abstract contract ERC4626WrapperFactory is ERC4626Factory, Trust {
    /// -----------------------------------------------------------------------
    /// Params
    /// -----------------------------------------------------------------------

    /// @notice Wrapper admin
    address public restrictedAdmin;

    /// @notice Rewards recipient
    address public rewardsRecipient;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _restrictedAdmin, address _rewardsRecipient) Trust(msg.sender) {
        restrictedAdmin = _restrictedAdmin;
        rewardsRecipient = _rewardsRecipient;
    }

    /// -----------------------------------------------------------------------
    /// Admin functions
    /// -----------------------------------------------------------------------
    function setRestrictedAdmin(address _restrictedAdmin) external requiresTrust {
        emit RestrictedAdminChanged(restrictedAdmin, _restrictedAdmin);
        restrictedAdmin = _restrictedAdmin;
    }

    function setRewardsRecipient(address _recipient) external requiresTrust {
        emit RewardsRecipientChanged(rewardsRecipient, _recipient);
        rewardsRecipient = _recipient;
    }

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event RestrictedAdminChanged(address indexed restrictedAdmin, address indexed newRestrictedAdmin);
    event RewardsRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
}
