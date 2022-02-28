// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @title Price Oracle
/// @author Compound
abstract contract CToken {
    function underlying() external view returns (address);
}
