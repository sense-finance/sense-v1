// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

// Internal references
import { ERC4626Adapter } from "../../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { MockToken } from "./MockToken.sol";
import { MockTarget } from "./MockTarget.sol";
import { IClaimer } from "../../../adapters/abstract/IClaimer.sol";
import { Trust } from "@sense-finance/v1-utils/Trust.sol";

contract MockClaimer is IClaimer {
    address[] public rewardTokens;
    address public target;
    bool public transfer = true;

    constructor(address _adapter, address[] memory _rewardTokens) {
        target = ERC4626Adapter(_adapter).target();
        rewardTokens = _rewardTokens;
    }

    function claim() external virtual {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            MockToken(rewardTokens[i]).mint(address(msg.sender), 60 * 10**MockToken(rewardTokens[i]).decimals());
        }
        if (transfer) {
            ERC20(target).transfer(msg.sender, ERC20(target).balanceOf(address(this)));
        }
    }

    function setTransfer(bool _transfer) external {
        transfer = _transfer;
    }
}
