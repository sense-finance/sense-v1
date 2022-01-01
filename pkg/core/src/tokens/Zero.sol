// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

/// @title Base Token
contract Token is ERC20, Trust {
    uint256 public immutable BASE_UNIT;

    constructor(
        address _adapter,
        uint8 _decimals,
        address _trusted
    )
        ERC20(
            string(abi.encodePacked(name, " ", datestring, " ", ZERO_NAME_PREFIX, " #", adapterId, " by Sense")),
            string(abi.encodePacked(name, " ", datestring, " ", ZERO_NAME_PREFIX, " #", adapterId, " by Sense")),
            18
        )
        Trust(_trusted)
    {
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
