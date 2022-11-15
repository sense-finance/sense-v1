// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity  0.8.15;

contract Versioning {
    string public version;
    constructor(string memory _version){
        version = _version;
    }
}
