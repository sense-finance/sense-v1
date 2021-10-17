// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @title Price Oracle
/// @author Compound
/// @notice The minimum interface a contract must implement in order to work as an oracle in Fuse
/// Taken from: https://github.com/Rari-Capital/compound-protocol/blob/fuse-final/contracts/PriceOracle.sol
abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice Get the underlying price of a cToken asset
    /// @param cToken The cToken to get the underlying price of
    /// @return The underlying asset price mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function getUnderlyingPrice(CTokenLike cToken) external view virtual returns (uint256);
}

interface CTokenLike {
    function underlying() external view returns (address);
}