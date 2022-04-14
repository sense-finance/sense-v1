// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { CropsFactory } from "../../../adapters/CropsFactory.sol";
import { CropFactory } from "../../../adapters/CropFactory.sol";
import { Divider } from "../../../Divider.sol";
import { MockCropsAdapter, MockAdapter } from "./MockAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "../../../adapters/BaseAdapter.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

interface MockTargetLike {
    function underlying() external view returns (address);
}

contract MockFactory is CropFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, _factoryParams, _reward) {}

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: _target,
            underlying: MockTargetLike(_target).underlying(),
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            ifee: factoryParams.ifee,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(new MockAdapter{ salt: _target.fillLast12Bytes() }(divider, adapterParams, reward));
    }
}

contract MockCropsFactory is CropsFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;
    address[] rewardTokens;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address[] memory _rewardTokens
    ) CropsFactory(_divider, _factoryParams) {
        rewardTokens = _rewardTokens;
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockCropsAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: _target,
            underlying: MockTargetLike(_target).underlying(),
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            ifee: factoryParams.ifee,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new MockCropsAdapter{ salt: _target.fillLast12Bytes() }(divider, adapterParams, rewardTokens)
        );
    }
}
