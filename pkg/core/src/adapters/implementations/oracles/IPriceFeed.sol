// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

interface IPriceFeed {
    function price() external view returns (uint256 price, uint256 updatedAt);
}
