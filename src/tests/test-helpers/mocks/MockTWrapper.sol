// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { MockToken } from "./MockToken.sol";

// Internal
import { BaseTWrapper } from "../../../wrappers/BaseTWrapper.sol";

/// @notice
contract MockTWrapper is BaseTWrapper {

    /* ========== MUTATIVE FUNCTIONS ========== */
    function _claimReward() internal override virtual {
        MockToken(reward).mint(address(this), 1e18);
    }

    function wrapUnderlying(uint256 amount) external virtual override returns (uint256) {
        // transfer from (underlying)
        // convert underlying to target
        MockToken(target).mint(msg.sender, amount);
        return amount;
    }

}
