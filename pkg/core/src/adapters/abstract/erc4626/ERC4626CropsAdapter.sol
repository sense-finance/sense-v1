// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC4626Adapter } from "./ERC4626Adapter.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { Crops } from "../extensions/Crops.sol";

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626CropsAdapter is ERC4626Adapter, Crops {
    constructor(
        address _divider,
        address _target,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) ERC4626Adapter(_divider, _target, _ifee, _adapterParams) Crops(_divider, _rewardTokens) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
    }
}
