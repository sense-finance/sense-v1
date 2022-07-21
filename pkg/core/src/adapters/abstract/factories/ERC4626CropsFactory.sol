// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Divider } from "../../../Divider.sol";
import { ERC4626CropsAdapter } from "../erc4626/ERC4626CropsAdapter.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { CropsFactory } from "./CropsFactory.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

contract ERC4626CropsFactory is CropsFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public supportedTargets;

    constructor(address _divider, FactoryParams memory _factoryParams) CropsFactory(_divider, _factoryParams) {}

    /// @notice Deploys an ERC4626Adapter contract
    /// @param _target The target address
    /// @param data ABI encoded data. Arguments:
    /// (1) Adapter type (0 for non-Crop and 1 for Crops adapters)
    /// (2) Reward tokens address array (if adapter is non-Crop, it expects an empty array)
    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        address[] memory rewardTokens = abi.decode(data, (address[]));

        /// Sanity checks
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

    /// @notice Sets `claimer` for given adapter.
    /// @param _claimer New claimer contract address
    function setClaimer(address _adapter, address _claimer) public requiresTrust {
        ERC4626CropsAdapter(_adapter).setClaimer(_claimer);
    }

    /* ========== LOGS ========== */

    event TargetSupported(address indexed target, bool indexed supported);
}
