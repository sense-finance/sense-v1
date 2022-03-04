// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { CToken } from "./CToken.sol";

/// @title Price Oracle
/// @author Compound
/// @notice The minimum interface a contract must implement in order to work as an oracle for Fuse with Sense
/// Original from: https://github.com/Rari-Capital/compound-protocol/blob/fuse-final/contracts/PriceOracle.sol
abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice Get the underlying price of a cToken asset
    /// @param cToken The cToken to get the underlying price of
    /// @return The underlying asset price mantissa (scaled by 1e18).
    /// 0 means the price is unavailable.
    function getUnderlyingPrice(CToken cToken) external view virtual returns (uint256);

    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// 0 means the price is unavailable.
    function price(address underlying) external view virtual returns (uint256);
}
