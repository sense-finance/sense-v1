// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @title IPriceFeed
/// @notice Returns prices of underlying tokens
/// @author Taken from: https://github.com/Rari-Capital/fuse-v1/blob/development/src/oracles/BasePriceOracle.sol
interface IPriceFeed {
    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return price The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function price(address underlying) external view returns (uint256 price);
}
