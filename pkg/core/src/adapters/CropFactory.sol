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

    // TODO: do we want this to be a function on the Periphery rather than here?
    /// @notice Replace existing reward tokens array with a new one and update adapters passed
    /// @param _rewardTokens array of rewards tokens addresses
    /// @param _adapters array of adapters to update the rewards tokens on
    function setRewardTokens(address[] memory _rewardTokens, address[] memory _adapters) public requiresTrust {
        for (uint256 i = 0; i < _adapters.length; i++) {
            CropAdapter(_adapters[i]).setRewardTokens(_rewardTokens);
        }
    }
}
