// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
//import "../libs/errors.sol";

// @title Access control via wards
// @notice You can use this contract to access control to specific methods by adding the modifier onlyWards()
contract Warded {
    mapping(address => uint256) public wards;

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function rely(address usr) external onlyWards {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external onlyWards {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyWards() {
        require(wards[msg.sender] == 1, "Sender must be authorized");
        //        require(wards[msg.sender] == 1, Errors.NotAuthorized);
        _;
    }

    /* ========== EVENTS ========== */
    
    event Rely(address indexed usr);
    event Deny(address indexed usr);
}
