// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

interface RateProvider {
    function getRate() external view returns (uint256);
}
