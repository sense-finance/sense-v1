// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { OwnableERC4626CropAdapter } from "../erc4626/OwnableERC4626CropAdapter.sol";
import { ERC4626CropFactory } from "./ERC4626CropFactory.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

// External references
import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";

/// @notice Ownable Crop Factory contract that deploys Ownable Crop Adapters for Rolling Liquidity Vaults
contract OwnableERC4626CropFactory is ERC4626CropFactory {
    using Bytes32AddressLib for address;

    /// @notice Rolling Liquidity Vault Factory address
    address public rlvFactory;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams,
        address _rlvFactory
    ) ERC4626CropFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams) {
        rlvFactory = _rlvFactory;
    }

    /// @notice Deploys an OwnableERC4626Adapter contract
    /// @param _target The target address
    /// @param data ABI encoded reward tokens address array
    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        address reward = abi.decode(data, (address));

        /// Sanity checks
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();
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
        // This will revert if an ERC4626 adapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        adapter = address(
            new OwnableERC4626CropAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                reward
            )
        );

        _setGuard(adapter);

        // Factory must have adapter auth so that it can give auth to the RLV
        OwnableERC4626CropAdapter(adapter).setIsTrusted(rlvFactory, true);

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }

    /// @notice Modify RLV Factory address
    /// @param _rlvFactory Address of the new factory
    function setRlvFactory(address _rlvFactory) external requiresTrust {
        rlvFactory = _rlvFactory;
        emit RlvFactoryChanged(_rlvFactory);
    }

    /* ========== LOGS ========== */

    event RlvFactoryChanged(address indexed rlvFactory);
}
