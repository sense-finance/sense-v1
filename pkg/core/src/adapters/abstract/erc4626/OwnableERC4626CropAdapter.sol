// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ERC4626CropAdapter } from "./ERC4626CropAdapter.sol";

interface Opener {
    function onSponsorWindowOpened(address, uint256) external;
}

/// @notice Ownable Crop Adapter contract for Rolling Liquidity Vaults
/// This adapter allows only the owner, which must comply with the Opener
/// interface, to Sponsor a Series
contract OwnableERC4626CropAdapter is ERC4626CropAdapter {
    uint256 internal open = 1;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626CropAdapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams, _reward) {}

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
}
