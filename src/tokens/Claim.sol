pragma solidity ^0.8.6;

// External references
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Internal references
import "../Divider.sol";
import "./BaseToken.sol";

// @title Claim token contract that allows excess collection pre-maturity
contract Claim is BaseToken {
    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) BaseToken(_maturity, _divider, _feed, _name, _symbol) {}

    function collect() external returns (uint256 _collected) {
        return Divider(divider).collect(msg.sender, feed, maturity, balanceOf(msg.sender));
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        super.transfer(to, value);
        Divider(divider).collect(msg.sender, feed, maturity, balanceOf(msg.sender));
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        super.transferFrom(from, to, value);
        Divider(divider).collect(msg.sender, feed, maturity, balanceOf(msg.sender));
        return true;
    }
}
