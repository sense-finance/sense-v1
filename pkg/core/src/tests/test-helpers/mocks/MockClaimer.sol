// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

// Internal references
import { ERC4626Adapter } from "../../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { MockToken } from "./MockToken.sol";
import { MockTarget } from "./MockTarget.sol";
import { IClaimer } from "../../../adapters/abstract/IClaimer.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

contract MockClaimer is IClaimer {
    address[] public rewardTokens;

    constructor(address _adapter, address[] memory _rewardTokens) {
        ERC20(ERC4626Adapter(_adapter).target()).approve(_adapter, type(uint256).max);
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            ERC20(_rewardTokens[i]).approve(_adapter, type(uint256).max);
        }
        rewardTokens = _rewardTokens;
    }

    function claim() external virtual {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            MockToken(rewardTokens[i]).mint(address(this), 60 * 10**MockToken(rewardTokens[i]).decimals());
        }
    }
}
