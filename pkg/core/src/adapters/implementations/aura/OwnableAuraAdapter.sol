// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { AuraAdapter } from "./AuraAdapter.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";

interface Opener {
    function onSponsorWindowOpened(address, uint256) external;
}

/// @notice Adapter contract for Aura Vaults (aToken)
contract OwnableAuraAdapter is AuraAdapter {
    uint256 internal open = 1;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) AuraAdapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams, _rewardTokens) {}

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
