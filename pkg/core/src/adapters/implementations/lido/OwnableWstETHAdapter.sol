// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { WstETHAdapter } from "../../implementations/lido/WstETHAdapter.sol";

interface Opener {
    function onSponsorWindowOpened(address, uint256) external;
}

/// @notice Adapter contract for wstETH
contract OwnableWstETHAdapter is WstETHAdapter {
    /// @notice Ownabale param
    uint256 internal open = 1;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams
    ) WstETHAdapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) {}

    function openSponsorWindow() external requiresTrust {
        open = 2;
        Opener(msg.sender).onSponsorWindowOpened(adapterParams.stake, adapterParams.stakeSize);
        open = 1;
    }

    function getMaturityBounds() external view override returns (uint256, uint256) {
        return open == 2 ? (adapterParams.minm, adapterParams.maxm) : (0, 0);
    }
}
