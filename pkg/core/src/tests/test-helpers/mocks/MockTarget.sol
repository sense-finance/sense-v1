// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { MockToken, AuthdMockToken } from "./MockToken.sol";
import { ERC20 as ZeppelinERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
