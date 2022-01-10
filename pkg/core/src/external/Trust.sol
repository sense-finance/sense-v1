// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.0;

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

/// @notice Ultra minimal authorization logic for smart contracts.
/// @author Taken from https://github.com/Rari-Capital/solmate/blob/fab107565a51674f3a3b5bfdaacc67f6179b1a9b/src/auth/Trust.sol
abstract contract Trust {
    event UserTrustUpdated(address indexed user, bool trusted);

    mapping(address => bool) public isTrusted;

    constructor(address initialUser) {
        isTrusted[initialUser] = true;

        emit UserTrustUpdated(initialUser, true);
    }

    function setIsTrusted(address user, bool trusted) public virtual requiresTrust {
        isTrusted[user] = trusted;

        emit UserTrustUpdated(user, trusted);
    }

    modifier requiresTrust() {
        if (!isTrusted[msg.sender]) revert Errors.Untrusted();

        _;
    }
}
