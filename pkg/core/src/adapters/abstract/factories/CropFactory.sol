// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { Crop } from "../extensions/Crop.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public reward;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams,
        address _reward
    ) BaseFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams) {
        reward = _reward;
    }
}
