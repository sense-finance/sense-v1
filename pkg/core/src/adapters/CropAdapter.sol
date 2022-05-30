// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { BaseAdapter } from "./BaseAdapter.sol";
import { Crop } from "./crops/Crop.sol";

abstract contract CropAdapter is BaseAdapter, Crop {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address _reward
    ) Crop(_divider, _reward) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
        Crop.notify(_usr, amt, join);
    }
}
