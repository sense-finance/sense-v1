// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { BaseAdapter } from "./BaseAdapter.sol";
import { Crops } from "./crops/Crops.sol";

abstract contract CropsAdapter is BaseAdapter, Crops {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) Crops(_divider, _rewardTokens) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        Crops.notify(_usr, amt, join);
    }
}
