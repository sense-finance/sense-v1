// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { MockToken } from "./MockToken.sol";

contract MockTarget is MockToken {
    address public underlying;
    constructor(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimal
    ) MockToken(_name, _symbol, _decimal) {
        underlying = _underlying;
    }
}
