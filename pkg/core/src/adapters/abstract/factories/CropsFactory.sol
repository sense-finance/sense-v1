// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Crops } from "../extensions/Crops.sol";
import { BaseFactory } from "./BaseFactory.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

abstract contract CropsFactory is BaseFactory {
    constructor(
        address _divider,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams
    ) BaseFactory(_divider, _rewardsRecipient, _factoryParams) {}

    /// @notice Update reward tokens for given adapters
    /// @param _rewardTokens array of rewards tokens addresses
    /// @param _adapters array of adapters to update the rewards tokens on
    function setRewardTokens(address[] memory _adapters, address[] memory _rewardTokens) public requiresTrust {
        for (uint256 i = 0; i < _adapters.length; i++) {
            Crops(_adapters[i]).setRewardTokens(_rewardTokens);
        }
    }

    /// @notice Sets `claimer` for a given adapter
    /// @param _claimer New claimer contract address
    function setClaimer(address _adapter, address _claimer) public requiresTrust {
        Crops(_adapter).setClaimer(_claimer);
    }
}
