// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

interface ERC20Like {
    function mint(address, uint256) external;
}

contract MultiMint {
    address public owner;
    constructor() {
        owner = msg.sender;
    }

    /// @dev Assumes this contract has authority over the passed in tokens
    function mint(address[] calldata _tokens, uint256[] calldata _amounts, address _user) external {
        require(msg.sender == owner, "ONLY_OWNER");
        require(_tokens.length == _amounts.length, "ARRAY_LENGTH_MISMATCH");

        for (uint256 i = 0; i < _tokens.length; i++) {
            ERC20Like(_tokens[i]).mint(_user, _amounts[i]);
        }
    }
}
