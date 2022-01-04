// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

contract Versioning {
    string public version;
    constructor(string memory _version){
        version = _version;
    }
}
