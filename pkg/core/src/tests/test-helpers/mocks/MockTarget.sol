// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { MockToken, AuthdMockToken } from "./MockToken.sol";

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

contract AuthdMockTarget is AuthdMockToken {
    address public underlying;

    constructor(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint8 _decimal
    ) AuthdMockToken(_name, _symbol, _decimal) {
        underlying = _underlying;
    }
}