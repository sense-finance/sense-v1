// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "solmate/erc20/ERC20.sol";

contract MockToken is ERC20 {

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) {}

    function mint(address account, uint256 amount) external virtual {
        _mint(account, amount);
    }
}
