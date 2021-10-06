// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import {Token} from "solmate/erc20/ERC20.sol";
import "../access/Warded.sol";

contract Token is ERC20, Warded {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) Warded() {}

     /// @param usr The address to send the minted tokens
     /// @param amount The amount to be minted
    function mint(address usr, uint256 amount) public onlyWards {
        _mint(usr, amount);
        emit Mint(usr, amount);
    }

    /// @param usr The address from where to burn tokens from
    /// @param amount The amount to be burned
    function burn(address usr, uint256 amount) public onlyWards {
        _burn(usr, amount);
        emit Burn(usr, amount);
    }

    /* ========== EVENTS ========== */

    event Mint(address indexed usr, uint256 amount);
    event Burn(address indexed usr, uint256 amount);
}
