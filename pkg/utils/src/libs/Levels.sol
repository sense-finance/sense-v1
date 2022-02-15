// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.0;

library Levels {
    uint256 private constant _INIT_BIT = 1;
    uint256 private constant _ISSUE_BIT = 2;
    uint256 private constant _COMBINE_BIT = 4;
    uint256 private constant _COLLECT_BIT = 8;
    uint256 private constant _REDEEM_ZERO_BIT = 16;
    uint256 private constant _REDEEM_ZERO_HOOK_BIT = 32;

    function initRestricted(uint256 level) internal pure returns (bool) {
        return level & _INIT_BIT != _INIT_BIT;
    }

    function issueRestricted(uint256 level) internal pure returns (bool) {
        return level & _ISSUE_BIT != _ISSUE_BIT;
    }

    function combineRestricted(uint256 level) internal pure returns (bool) {
        return level & _COMBINE_BIT != _COMBINE_BIT;
    }

    function collectDisabled(uint256 level) internal pure returns (bool) {
        return level & _COLLECT_BIT != _COLLECT_BIT;
    }

    function redeemZeroRestricted(uint256 level) internal pure returns (bool) {
        return level & _REDEEM_ZERO_BIT != _REDEEM_ZERO_BIT;
    }

    function redeemZeroHookDisabled(uint256 level) internal pure returns (bool) {
        return level & _REDEEM_ZERO_HOOK_BIT != _REDEEM_ZERO_HOOK_BIT;
    }
}
