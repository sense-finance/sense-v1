// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { BaseAdapter } from "../BaseAdapter.sol";
import { ERC4626Adapter } from "./ERC4626Adapter.sol";
import { Crop } from "../extensions/Crop.sol";

interface Opener {
    function onSponsorWindowOpened(address, uint256) external;
}

/// @notice Ownable Crop Adapter contract for Rolling Liquidity Vaults
/// This adapter allows only the owner, which must comply with the Opener
/// interface, to Sponsor a Series
contract OwnableERC4626CropAdapter is ERC4626Adapter, Crop {
    uint256 internal open = 1;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) Crop(_divider, _reward) {}

    function openSponsorWindow() external requiresTrust {
        open = 2;
        Opener(msg.sender).onSponsorWindowOpened(adapterParams.stake, adapterParams.stakeSize);
        open = 1;
    }

    // @notice If the Sponsor Window is open (which can only be done by the owner of this contract),
    // return the maturity bounds. Otherwise, return 0 making the sponsoring to revert.
    function getMaturityBounds() external view override returns (uint256, uint256) {
        return open == 2 ? (adapterParams.minm, adapterParams.maxm) : (0, 0);
    }

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
