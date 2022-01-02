// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { CropAdapter } from "./CropAdapter.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public immutable reward;

    constructor(
        address _divider,
        address _protocol,
        address _adapterImpl,
        FactoryParams memory _factoryParams,
        address _reward
    ) BaseFactory(_divider, _protocol, _adapterImpl, _factoryParams) {
        reward = _reward;
    }

    function deployAdapter(address _target) external override returns (address adapterClone) {
        require(_exists(_target), Errors.NotSupported);

        adapterClone = Clones.cloneDeterministic(adapterImpl, Bytes32AddressLib.fillLast12Bytes(_target));
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: _target,
            delta: factoryParams.delta,
            oracle: factoryParams.oracle,
            ifee: factoryParams.ifee,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode
        });

        CropAdapter(adapterClone).initialize(divider, adapterParams, reward);
        Divider(divider).setAdapter(adapterClone, true);

        emit AdapterDeployed(adapterClone, _target);

        return adapterClone;
    }
}
