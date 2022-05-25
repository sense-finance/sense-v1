// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { CropsFactory } from "../../../adapters/CropsFactory.sol";
import { CropFactory } from "../../../adapters/CropFactory.sol";
import { Divider } from "../../../Divider.sol";
import { MockAdapter, Mock4626Adapter, MockCropsAdapter, Mock4626CropsAdapter } from "./MockAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "../../../adapters/BaseAdapter.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

interface MockTargetLike {
    function underlying() external view returns (address);

    function asset() external view returns (address);
}

contract MockFactory is CropFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;
    bool public is4626;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward,
        bool _is4626
    ) CropFactory(_divider, _factoryParams, _reward) {
        is4626 = _is4626;
    }

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
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        if (is4626) {
            adapter = address(
                new Mock4626Adapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    MockTargetLike(_target).asset(),
                    factoryParams.ifee,
                    adapterParams,
                    reward
                )
            );
        } else {
            adapter = address(
                new MockAdapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    MockTargetLike(_target).underlying(),
                    factoryParams.ifee,
                    adapterParams,
                    reward
                )
            );
        }
    }
}

contract MockCropsFactory is CropsFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;
    address[] rewardTokens;
    bool public is4626;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address[] memory _rewardTokens,
        bool _is4626
    ) CropsFactory(_divider, _factoryParams) {
        rewardTokens = _rewardTokens;
        is4626 = _is4626;
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
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });

        if (is4626) {
            adapter = address(
                new Mock4626CropsAdapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    MockTargetLike(_target).asset(),
                    factoryParams.ifee,
                    adapterParams,
                    rewardTokens
                )
            );
        } else {
            adapter = address(
                new MockCropsAdapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    MockTargetLike(_target).underlying(),
                    factoryParams.ifee,
                    adapterParams,
                    rewardTokens
                )
            );
        }
    }
}
