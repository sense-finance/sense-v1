// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public immutable reward;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) BaseFactory(_divider, _factoryParams) {
        reward = _reward;
    }
}
