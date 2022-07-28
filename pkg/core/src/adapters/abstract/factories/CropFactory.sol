// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Crop } from "../extensions/Crop.sol";
import { BaseFactory } from "./BaseFactory.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

abstract contract CropFactory is Trust, BaseFactory {
    address public reward;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) Trust(msg.sender) BaseFactory(_divider, _factoryParams) {
        reward = _reward;
    }

    /// @notice Update reward token for given adapter
    /// @param _adapter address of adapter to update the reward token on
    /// @param _rewardToken address of reward token
    function setRewardTokens(address _adapter, address _rewardToken) public requiresTrust {
        Crop(_adapter).setRewardToken(_rewardToken);
    }

    /// @notice Sets `claimer` for a given adapter
    /// @param _claimer New claimer contract address
    function setClaimer(address _adapter, address _claimer) public requiresTrust {
        Crop(_adapter).setClaimer(_claimer);
    }
}
