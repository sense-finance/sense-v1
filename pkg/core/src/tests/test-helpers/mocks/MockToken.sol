// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimal
    ) ERC20(_name, _symbol, _decimal) {}

    function mint(address account, uint256 amount) external virtual {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external virtual {
        _burn(account, amount);
    }
}
