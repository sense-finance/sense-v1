// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

/// @title Base Token
contract Token is ERC20, Trust {

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _trusted
    ) ERC20(_name, _symbol, _decimals) Trust(_trusted) { }

    /// @param usr The address to send the minted tokens
    /// @param amount The amount to be minted
    function mint(address usr, uint256 amount) public requiresTrust {
        _mint(usr, amount);
    }

    /// @param usr The address from where to burn tokens from
    /// @param amount The amount to be burned
    function burn(address usr, uint256 amount) public requiresTrust {
        _burn(usr, amount);
    }
}