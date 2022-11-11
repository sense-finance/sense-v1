// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import { ERC4626Adapter } from "./ERC4626Adapter.sol";

interface Opener {
    function onSponsorWindowOpened(address, uint256) external;
}

/// @notice Ownable Adapter contract for Rolling Liquidity Vaults
contract OwnableERC4626Adapter is ERC4626Adapter {
    uint256 internal open = 1;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) {}

    function openSponsorWindow() external requiresTrust {
        open = 2;
        Opener(msg.sender).onSponsorWindowOpened(adapterParams.stake, adapterParams.stakeSize);
        open = 1;
    }

    function getMaturityBounds() external view override returns (uint256, uint256) {
        return open == 2 ? (adapterParams.minm, adapterParams.maxm) : (0, 0);
    }
}
