// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { Divider } from "../Divider.sol";
import { Token } from "./Token.sol";

/// @title Claim Token
/// @notice Strips off excess before every transfer
contract Claim is Token {
    address public immutable adapter;
    uint48 public immutable maturity;
    address public immutable divider;

    constructor(
        address _adapter,
        uint48 _maturity,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _divider
    ) Token(_name, _symbol, _decimals, _divider) {
        adapter = _adapter;
        maturity = _maturity;
        divider = _divider;
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
