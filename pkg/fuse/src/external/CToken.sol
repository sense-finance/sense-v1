// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @title Price Oracle
/// @author Compound
interface CToken {
    function underlying() external view returns (address);

    function mint(uint256 mintAmount) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function decimals() external view returns (uint8);
}