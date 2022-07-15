// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

interface IPriceFeed {
    /// @dev Returns the price in ETH of `underlying` (implements `BasePriceOracle`).
    /// This function must return a non-stale, greater than 0 price.
    function price(address underlying) external view returns (uint256 price);
}
