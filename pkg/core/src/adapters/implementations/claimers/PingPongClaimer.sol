// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

// Internal references
import { IClaimer } from "../../../adapters/abstract/IClaimer.sol";
import { BaseAdapter } from "../../../adapters/abstract/BaseAdapter.sol";

/// @title ExtractableReward
/// @dev This claimer only returns the received target back to the adapter. This is because
/// target has automatic rewards claiming which is triggered when transferring the target.
contract PingPongClaimer is IClaimer {
    function claim(address adapter) external virtual {
        ERC20 target = ERC20(BaseAdapter(adapter).target());
        target.transfer(adapter, target.balanceOf(address(this)));
    }
}
