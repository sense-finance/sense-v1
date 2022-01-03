// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { DateTime } from "../external/DateTime.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

/// @title Zero Token
contract Zero is ERC20, Trust {
    string private constant ZERO_SYMBOL_PREFIX = "z";
    string private constant ZERO_NAME_PREFIX = "Zero";

    constructor(
        address _divider,
        address _adapter,
        uint48 _maturity
    ) ERC20("", "", 18) Trust(_divider) {
        ERC20 target = ERC20(Adapter(_adapter).getTarget());
        (, string memory m, string memory y) = DateTime.toDateString(_maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory adapterId = DateTime.uintToString(Divider(_divider).adapterIDs(_adapter));

        name = string(
            abi.encodePacked(target.name(), " ", datestring, " ", ZERO_NAME_PREFIX, " #", adapterId, " by Sense")
        );
        symbol = string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId));
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
