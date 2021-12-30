// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CropFactory } from "../../../adapters/CropFactory.sol";
import { Divider } from "../../../Divider.sol";
import { MockAdapter } from "./MockAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract MockFactory is CropFactory {
    mapping(address => bool) public targets;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, address(0), _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target) external override returns (address adapterAddress) {
        MockAdapter adapter = new MockAdapter(divider, _target, factoryParams.oracle, factoryParams.delta, factoryParams.ifee, factoryParams.stake, factoryParams.stakeSize, factoryParams.minm, factoryParams.maxm, factoryParams.mode, reward);

        _addAdapter(address(adapter));

        return address(adapter);
    }
}
