// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

library Levels {
    uint256 private constant _ISSUE_BIT = 0;
    uint256 private constant _COMBINE_BIT = 1;
    uint256 private constant _COLLECT_BIT = 2;
    uint256 private constant _REDEEM_HOOK_BIT = 3;

    function issueEnabled(uint256 level) internal pure returns (bool) {
        return level & (2**_ISSUE_BIT) == 2**_ISSUE_BIT;
    }
    function combineEnabled(uint256 level) internal pure returns (bool) {
        return level & (2**_COMBINE_BIT) == 2**_COMBINE_BIT;
    }

    function collectEnabled(uint256 level) internal pure returns (bool) {
        return level & (2**_COLLECT_BIT) == 2**_COLLECT_BIT;
    }

    function redeemZeroHookEnabled(uint256 level) internal pure returns (bool) {
        return level & (2**_REDEEM_HOOK_BIT) == 2**_REDEEM_HOOK_BIT;
    }
}