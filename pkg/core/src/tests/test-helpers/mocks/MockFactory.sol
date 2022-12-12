// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { BaseFactory } from "../../../adapters/abstract/factories/BaseFactory.sol";
import { CropFactory } from "../../../adapters/abstract/factories/CropFactory.sol";
import { ERC4626Factory } from "../../../adapters/abstract/factories/ERC4626Factory.sol";
import { ExtractableReward } from "../../../adapters/abstract/extensions/ExtractableReward.sol";
import { Divider } from "../../../Divider.sol";
import { MockAdapter, MockCropsAdapter, MockCropAdapter, Mock4626Adapter, Mock4626CropAdapter, Mock4626CropsAdapter } from "./MockAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { BaseAdapter } from "../../../adapters/abstract/BaseAdapter.sol";

// External references
import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

interface MockTargetLike {
    function underlying() external view returns (address);

    function asset() external view returns (address);
}

// -- Non-4626 factories -- //

contract MockFactory is BaseFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        BaseFactory.FactoryParams memory _factoryParams
    ) BaseFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams) {}

    function supportTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external virtual override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new MockAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).underlying(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams
            )
        );

        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            Divider(divider).setGuard(adapter, type(uint256).max);
        }

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}

contract MockCropFactory is CropFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        BaseFactory.FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams, _reward) {}

    function supportTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external virtual override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockCropsAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new MockCropAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).underlying(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                reward
            )
        );

        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            Divider(divider).setGuard(adapter, type(uint256).max);
        }

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}

contract MockCropsFactory is BaseFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;
    address[] rewardTokens;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        BaseFactory.FactoryParams memory _factoryParams,
        address[] memory _rewardTokens
    ) BaseFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams) {
        rewardTokens = _rewardTokens;
    }

    function supportTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockCropsAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new MockCropsAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).underlying(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                rewardTokens
            )
        );

        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            Divider(divider).setGuard(adapter, type(uint256).max);
        }

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}

// -- 4626 factories -- //

contract Mock4626CropFactory is CropFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        BaseFactory.FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams, _reward) {}

    function supportTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external virtual override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new Mock4626CropAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).asset(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                reward
            )
        );

        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            Divider(divider).setGuard(adapter, type(uint256).max);
        }

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}

contract Mock4626CropsFactory is BaseFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;
    address[] rewardTokens;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        BaseFactory.FactoryParams memory _factoryParams,
        address[] memory _rewardTokens
    ) BaseFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams) {
        rewardTokens = _rewardTokens;
    }

    function supportTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        if (!targets[_target]) revert Errors.TargetNotSupported();
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a MockCropsAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        adapter = address(
            new Mock4626CropsAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).asset(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                rewardTokens
            )
        );

        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            Divider(divider).setGuard(adapter, type(uint256).max);
        }

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}
