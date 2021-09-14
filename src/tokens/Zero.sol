pragma solidity ^0.8.6;

// External references
import "../external/tokens/ERC20.sol";

// Internal references
import "./BaseToken.sol";

// @title Zero token contract that allows Divider contract to burn Zero tokens for any address
contract Zero is BaseToken {
    constructor(
        uint256 _maturity,
        address _divider,
        address _feed,
        string memory _name,
        string memory _symbol
    ) BaseToken(_maturity, _divider, _feed, _name, _symbol) {}
}
