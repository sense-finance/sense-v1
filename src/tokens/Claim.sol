// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
import "../Divider.sol";
import "./Token.sol";

// @title Claim token contract that allows excess collection pre-maturity
contract Claim is Token {
    uint256 public maturity;
    address public divider;
    address public feed;

    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) Token(_name, _symbol) {
        maturity = _maturity;
        divider = _divider;
        feed = _feed;
    }

    function collect() external returns (uint256 _collected) {
        return Divider(divider).collect(msg.sender, feed, maturity);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        super.transfer(to, value);
        Divider(divider).collect(msg.sender, feed, maturity);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        super.transferFrom(from, to, value);
        Divider(divider).collect(msg.sender, feed, maturity);
        return true;
    }
}
