// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import {ERC20} from "solmate/erc20/ERC20.sol";
import {Trust} from "solmate/auth/Trust.sol";

contract Token is ERC20, Trust {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) Trust(msg.sender) {}

     /// @param usr The address to send the minted tokens
     /// @param amount The amount to be minted
    function mint(address usr, uint256 amount) public requiresTrust {
        _mint(usr, amount);
        emit Mint(usr, amount);
    }

    /// @param usr The address from where to burn tokens from
    /// @param amount The amount to be burned
    function burn(address usr, uint256 amount) public requiresTrust {
        _burn(usr, amount);
        emit Burn(usr, amount);
    }

    /* ========== EVENTS ========== */

    event Mint(address indexed usr, uint256 amount);
    event Burn(address indexed usr, uint256 amount);
}
