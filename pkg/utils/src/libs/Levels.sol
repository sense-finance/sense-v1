// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

library Levels {
    uint256 private constant _INIT_BIT = 0;
    uint256 private constant _ISSUE_BIT = 1;
    uint256 private constant _COMBINE_BIT = 2;
    uint256 private constant _COLLECT_BIT = 3;
    uint256 private constant _REDEEM_ZERO_BIT = 4;
    uint256 private constant _REDEEM_ZERO_HOOK_BIT = 5;

    function initRestricted(uint256 level) internal pure returns (bool) {
        return level & (2**_INIT_BIT) != 2**_INIT_BIT;
    }

    function issueRestricted(uint256 level) internal pure returns (bool) {
        return level & (2**_ISSUE_BIT) != 2**_ISSUE_BIT;
    }

    function combineRestricted(uint256 level) internal pure returns (bool) {
        return level & (2**_COMBINE_BIT) != 2**_COMBINE_BIT;
    }

    function collectDisabled(uint256 level) internal pure returns (bool) {
        return level & (2**_COLLECT_BIT) != 2**_COLLECT_BIT;
    }

    function redeemZeroRestricted(uint256 level) internal pure returns (bool) {
        return level & (2**_REDEEM_ZERO_BIT) != 2**_REDEEM_ZERO_BIT;
    }

    function redeemZeroHookDisabled(uint256 level) internal pure returns (bool) {
        return level & (2**_REDEEM_ZERO_HOOK_BIT) != 2**_REDEEM_ZERO_HOOK_BIT;
    }
}