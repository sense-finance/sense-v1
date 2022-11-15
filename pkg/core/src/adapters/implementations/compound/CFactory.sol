// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { CropFactory } from "../../abstract/factories/CropFactory.sol";
import { CAdapter, ComptrollerLike } from "./CAdapter.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
import { Divider } from "../../../Divider.sol";

// External references
import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

interface CTokenLike {
    function underlying() external view returns (address);
}

contract CFactory is CropFactory {
    using Bytes32AddressLib for address;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams, _reward) {}

    function deployAdapter(address _target, bytes memory) external override returns (address adapter) {
        // Sanity check
        if (Divider(divider).periphery() != msg.sender) revert Errors.OnlyPeriphery();

        (bool isListed, , ) = ComptrollerLike(COMPTROLLER).markets(_target);
        if (!isListed) revert Errors.TargetNotSupported();

        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a CAdapter with the provided target has already
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
            new CAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                _target == CETH ? WETH : CTokenLike(_target).underlying(),
                rewardsRecipient,
                factoryParams.ifee,
                adapterParams,
                reward
            )
        );

        _setGuard(adapter);

        ExtractableReward(adapter).setIsTrusted(restrictedAdmin, true);
    }
}
