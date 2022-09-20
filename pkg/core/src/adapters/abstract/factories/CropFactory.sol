// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Crop } from "../extensions/Crop.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public reward;

    constructor(
        address _divider,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams,
        address _reward
    ) BaseFactory(_divider, _rewardsRecipient, _factoryParams) {
        reward = _reward;
    }

    /// @notice Update reward token for given adapter
    /// @param _adapter address of adapter to update the reward token on
    /// @param _rewardToken address of reward token
    function setRewardToken(address _adapter, address _rewardToken) public requiresTrust {
        Crop(_adapter).setRewardToken(_rewardToken);
    }

    /// @notice Sets `claimer` for a given adapter
    /// @param _claimer New claimer contract address
    function setClaimer(address _adapter, address _claimer) public requiresTrust {
        Crop(_adapter).setClaimer(_claimer);
    }
}
