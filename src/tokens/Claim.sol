// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { Divider } from "../Divider.sol";
import { Token } from "./Token.sol";

/// @title Claim token contract that allows excess collection pre-maturity
contract Claim is Token {
    uint256 public maturity;
    address public divider;
    address public feed;

    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) Token(_name, _symbol, _decimals) {
        maturity = _maturity;
        divider = _divider;
        feed = _feed;
    }

    function collect() external returns (uint256 _collected) {
        return Divider(divider).collect(msg.sender, feed, maturity, address(0));
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        Divider(divider).collect(msg.sender, feed, maturity, to);
        super.transfer(to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        Divider(divider).collect(from, feed, maturity, to);
        super.transferFrom(from, to, value);
        return true;
    }
}
