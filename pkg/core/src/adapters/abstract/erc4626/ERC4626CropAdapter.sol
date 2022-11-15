// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ERC4626Adapter } from "./ERC4626Adapter.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { Crop } from "../extensions/Crop.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626CropAdapter is ERC4626Adapter, Crop {
    using SafeTransferLib for ERC20;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) Crop(_divider, _reward) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
        super.notify(_usr, amt, join);
    }

    function _isValid(address _token) internal override returns (bool) {
        return (_token != target && _token != adapterParams.stake && _token != reward);
    }
}
