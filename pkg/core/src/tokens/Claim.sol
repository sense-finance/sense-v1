// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { Divider } from "../Divider.sol";
import { Token } from "./Token.sol";

import { DateTime } from "../external/DateTime.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

/// @title Claim Token
/// @notice Strips off excess before every transfer
contract Claim is Token {
    string private constant CLAIM_SYMBOL_PREFIX = "c";
    string private constant CLAIM_NAME_PREFIX = "Claim";

    uint48 public immutable maturity;
    address public immutable divider;
    address public immutable adapter;

    constructor(
        address _divider,
        address _adapter,
        uint48 _maturity
    ) Token("", "", 18, _divider) {
        divider = _divider;
        adapter = _adapter;
        maturity = _maturity;

        ERC20 target = ERC20(Adapter(_adapter).getTarget());
        (, string memory m, string memory y) = DateTime.toDateString(_maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory adapterId = DateTime.uintToString(Divider(_divider).adapterIDs(_adapter));

        name = string(abi.encodePacked(target.name(), " ", datestring, " ", CLAIM_NAME_PREFIX, " #", adapterId, " by Sense"));
        symbol = string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId));
    }

    function collect() external returns (uint256 _collected) {
        return Divider(divider).collect(msg.sender, adapter, maturity, 0, address(0));
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        Divider(divider).collect(msg.sender, adapter, maturity, value, to);
        return super.transfer(to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        Divider(divider).collect(from, adapter, maturity, value, to);
        return super.transferFrom(from, to, value);
    }
}
