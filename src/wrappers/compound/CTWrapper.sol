// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseTWrapper } from "../BaseTWrapper.sol";

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

// @title feed contract for cTokens
contract CTWrapper is BaseTWrapper {
    using FixedMath for uint256;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }
}
