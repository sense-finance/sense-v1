// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

/// @title Base Token
contract Token is ERC20, Trust {
    uint256 public immutable BASE_UNIT;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _trusted
    ) ERC20(_name, _symbol, _decimals) Trust(_trusted) {
        BASE_UNIT = 10**_decimals;
    }

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
