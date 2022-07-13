// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Divider } from "../../../Divider.sol";
import { ERC4626Adapter } from "../erc4626/ERC4626Adapter.sol";
import { ERC4626CropsAdapter } from "../erc4626/ERC4626CropsAdapter.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { BaseFactory } from "./BaseFactory.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

// External references
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

contract ERC4626Factory is BaseFactory, Trust {
    using Bytes32AddressLib for address;

    mapping(address => bool) public supportedTargets;

    constructor(address _divider, FactoryParams memory _factoryParams)
        BaseFactory(_divider, _factoryParams)
        Trust(msg.sender)
    {}

    /// @notice Deploys an ERC4626Adapter contract
    /// @param _target The target address
    /// @param data ABI encoded data. Arguments:
    /// (1) Adapter type (0 for non-Crop and 1 for Crops adapters)
    /// (2) Reward tokens address array (if adapter is non-Crop, it expects an empty array)
    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        (uint256 adapterType, address[] memory rewardTokens) = abi.decode(data, (uint256, address[]));

        /// Sanity checks
        if (adapterType != 0 && adapterType != 1) revert Errors.InvalidAdapterType();
        if (!Divider(divider).permissionless() && !supportedTargets[_target]) revert Errors.TargetNotSupported();

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

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a FAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        if (adapterType == 0) {
            adapter = address(
                new ERC4626Adapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    factoryParams.ifee,
                    adapterParams
                )
            );
        } else if (adapterType == 1) {
            adapter = address(
                new ERC4626CropsAdapter{ salt: _target.fillLast12Bytes() }(
                    divider,
                    _target,
                    factoryParams.ifee,
                    adapterParams,
                    rewardTokens
                )
            );
        }
    }

    /// @notice Set custom oracle for adapter
    /// @param _adapter The adapter address
    /// @param _oracle The oracle address
    function setOracle(address _adapter, address _oracle) external requiresTrust {
        ERC4626Adapter(_adapter).setOracle(_oracle);
    }

    /// @notice (Un)support target
    /// @param _target The target address
    /// @param supported Whether the target should be supported or not
    function supportTarget(address _target, bool supported) external requiresTrust {
        supportedTargets[_target] = supported;
        emit TargetSupported(_target, supported);
    }

    /// @notice (Un)support multiple target at once
    /// @param _targets Array of target addresses
    /// @param supported Whether the targets should be supported or not
    function supportTargets(address[] memory _targets, bool supported) external requiresTrust {
        for (uint256 i = 0; i < _targets.length; i++) {
            supportedTargets[_targets[i]] = supported;
            emit TargetSupported(_targets[i], supported);
        }
    }

    /// @notice Update reward tokens for given adapter
    /// @param _adapter adapter to set reward tokens for
    /// @param _rewardTokens array of rewards tokens addresses
    function setRewardTokens(address _adapter, address[] memory _rewardTokens) public requiresTrust {
        ERC4626CropsAdapter(_adapter).setRewardTokens(_rewardTokens);
    }

    /// @notice Update reward tokens for given adapters
    /// @param _rewardTokens array of rewards tokens addresses
    /// @param _adapters array of adapters to update the rewards tokens on
    function setRewardTokens(address[] memory _adapters, address[] memory _rewardTokens) public requiresTrust {
        for (uint256 i = 0; i < _adapters.length; i++) {
            ERC4626CropsAdapter(_adapters[i]).setRewardTokens(_rewardTokens);
        }
    }

    /* ========== LOGS ========== */

    event TargetSupported(address indexed target, bool indexed supported);
}
