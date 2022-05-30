// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC4626Adapter } from "./ERC4626Adapter.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Crop } from "./crops/Crop.sol";

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626CropAdapter is ERC4626Adapter, Crop {
    constructor(
        address _divider,
        address _target,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626Adapter(_divider, _target, _ifee, _adapterParams) Crop(_divider, _reward) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
        Crop.notify(_usr, amt, join);
    }
}
