// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.7.0;

library Levels {
    uint256 private constant _INIT_BIT = 0x1;
    uint256 private constant _ISSUE_BIT = 0x2;
    uint256 private constant _COMBINE_BIT = 0x4;
    uint256 private constant _COLLECT_BIT = 0x8;
    uint256 private constant _REDEEM_BIT = 0x10;
    uint256 private constant _REDEEM_HOOK_BIT = 0x20;

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

    function redeemRestricted(uint256 level) internal pure returns (bool) {
        return level & _REDEEM_BIT != _REDEEM_BIT;
    }

    function redeemHookDisabled(uint256 level) internal pure returns (bool) {
        return level & _REDEEM_HOOK_BIT != _REDEEM_HOOK_BIT;
    }
}
