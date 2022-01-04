// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { CropFactory } from "../../../adapters/CropFactory.sol";

contract MockFactory is CropFactory {
    mapping(address => bool) public targets;

    constructor(
        address _adapterImpl,
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, address(0), _adapterImpl, _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }
}
