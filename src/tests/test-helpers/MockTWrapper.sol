// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { MockToken } from "./mocks/MockToken.sol";

// Internal
import { BaseTWrapper } from "../../wrappers/BaseTWrapper.sol";

/// @notice
contract MockTWrapper is BaseTWrapper {

    /* ========== MUTATIVE FUNCTIONS ========== */
    function _claimReward() internal override virtual {
        MockToken(reward).mint(address(this), 1e18);
    }

}
