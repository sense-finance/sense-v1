// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

// Internal references
import { IClaimer } from "../../../adapters/abstract/IClaimer.sol";

/// @title ExtractableReward
/// @dev This claimer only returns the received target back to the adapter. This is because
/// target has automatic rewards claiming which is triggered when transferring the target.
contract PingPongClaimer is IClaimer {
    address public constant target = 0x14244978b1CC189324C3e35685D6Ae2F632e9846; // Angle sanFRAX_EUR Wrapper
    ERC20 public constant ANGLE = ERC20(0x14244978b1CC189324C3e35685D6Ae2F632e9846); // Angle sanFRAX_EUR Wrapper

    address public immutable adapter;

    constructor(address _adapter) {
        adapter = _adapter;
    }

    function claim() external virtual {
        ERC20 target = ERC20(target);
        target.transfer(adapter, target.balanceOf(address(this)));
    }
}
