// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

/// @title Fixed point arithmetic library
/// @author Taken from https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WDiv.sol & https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WMul.sol
library WadMath {

    /// @dev Base unit
    uint256 internal constant WAD = 1e18;

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Multiply an amount by a fixed point factor with 18 decimals, rounds down
    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
    unchecked { z /= 1e18; }
    }

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide an amount by a fixed point factor with 18 decimals, rounds down
    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * 1e18) / y;
    }
}
