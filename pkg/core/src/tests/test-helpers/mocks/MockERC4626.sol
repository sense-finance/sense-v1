// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "../../../adapters/abstract/erc4626/ERC4626.sol";

contract MockERC4626 is ERC4626 {
    uint256 public beforeWithdrawHookCalledCounter = 0;
    uint256 public afterDepositHookCalledCounter = 0;

    constructor(
        ERC20 _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC4626(_underlying, _name, _symbol, _decimals) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function beforeWithdraw(uint256, uint256) internal override {
        beforeWithdrawHookCalledCounter++;
    }

    function afterDeposit(uint256, uint256) internal override {
        afterDepositHookCalledCounter++;
    }
}
