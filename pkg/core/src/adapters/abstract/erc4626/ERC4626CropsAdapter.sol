// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ERC4626Adapter } from "./ERC4626Adapter.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { Crops } from "../extensions/Crops.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626CropsAdapter is ERC4626Adapter, Crops {
    using SafeTransferLib for ERC20;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) Crops(_divider, _rewardTokens) {}

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
    }

    function _isValid(address _token) internal override returns (bool) {
        for (uint256 i = 0; i < rewardTokens.length; ) {
            if (_token == rewardTokens[i]) return false;
            unchecked {
                ++i;
            }
        }

        // Check that token is neither the target nor the stake
        return (_token != target && _token != adapterParams.stake);
    }
}
