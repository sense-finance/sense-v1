// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { CropAdapter } from "./CropAdapter.sol";
import { BaseFactory } from "./BaseFactory.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

abstract contract CropFactory is Trust, BaseFactory {
    // address[] public rewardTokens;

    constructor(address _divider, FactoryParams memory _factoryParams)
        Trust(msg.sender)
        BaseFactory(_divider, _factoryParams)
    {}

    // /// @notice Replace existing reward tokens array with a new one
    // /// @dev Called by owner of the adapter factory, it will have an impact only on future deployed adapters
    // /// @param _rewardTokens array of rewards tokens addresses
    // function setRewardTokens(address[] memory _rewardTokens) public requiresTrust {
    //     rewardTokens = _rewardTokens;
    // }

    // TODO: we could remove the `setRewardTokens` on top but we would need to send and empty array when deploying, e.g, CAdapter
    // TODO: do we want this to be a function on the Periphery rather than here?
    /// @notice Replace existing reward tokens array with a new one
    /// @dev Called by owner of the adapter factory, it will impact future deployed adapters and will also
    /// update the adapters passed on `_adapters` array
    /// @param _rewardTokens array of rewards tokens addresses
    /// @param _adapters array of adapters to update the rewards tokens on
    function setRewardTokens(address[] memory _rewardTokens, address[] memory _adapters) public requiresTrust {
        // rewardTokens = _rewardTokens;

        for (uint256 i = 0; i < _adapters.length; i++) {
            CropAdapter(_adapters[i]).setRewardTokens(_rewardTokens);
        }
    }
}
