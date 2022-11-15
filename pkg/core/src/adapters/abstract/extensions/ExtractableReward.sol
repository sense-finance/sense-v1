// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

/// @title ExtractableReward
/// @notice Allows to extract rewards from the contract to the `rewardsRecepient`
abstract contract ExtractableReward is Trust {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// @notice Rewards recipient
    address public rewardsRecipient;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(address _rewardsRecipient) Trust(msg.sender) {
        rewardsRecipient = _rewardsRecipient;
    }

    /// -----------------------------------------------------------------------
    /// Rewards extractor
    /// -----------------------------------------------------------------------

    /// @notice Receives a token address and returns whether it is an
    /// extractable token or not
    /// @dev To be overriden by the inheriting contract
    function _isValid(address _token) internal virtual returns (bool);

    /// @notice Transfers reward tokens from the adapter to Sense's reward container
    function extractToken(address token) external {
        if (!_isValid(token)) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, t.balanceOf(address(this)));
        emit RewardsClaimed(token, rewardsRecipient, tBal);
    }

    /// -----------------------------------------------------------------------
    /// Admin functions
    /// -----------------------------------------------------------------------
    function setRewardsRecipient(address recipient) external requiresTrust {
        emit RewardsRecipientChanged(rewardsRecipient, recipient);
        rewardsRecipient = recipient;
    }

    /// -----------------------------------------------------------------------
    /// Logs
    /// -----------------------------------------------------------------------
    event RewardsRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event RewardsClaimed(address indexed token, address indexed recipient, uint256 indexed amount);
}
