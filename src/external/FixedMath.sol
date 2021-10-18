// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

/// @title Fixed point arithmetic library
/// @author Taken from https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WDiv.sol & https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WMul.sol
library FixedMath {
    uint256 internal constant WAD = 1e18;

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Multiply an amount by a fixed point factor with 18 decimals, rounds down
    function fmul(uint256 x, uint256 y, uint256 baseUnit) internal pure returns (uint256 z) {
        z = x * y;
    unchecked { z /= baseUnit; }
    }

    function fmulUp(uint x, uint y, uint256 baseUnit) internal pure returns (uint z) {
        z = x * y + baseUnit - 1;    // Rounds up.  So (again imagining 2 decimal places):
    unchecked { z /= baseUnit; }     // 383 (3.83) * 235 (2.35) -> 90005 (9.0005), + 99 (0.0099) -> 90104, / 100 -> 901 (9.01).
    }

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide an amount by a fixed point factor with 18 decimals, rounds down
    function fdiv(uint256 x, uint256 y, uint256 baseUnit) internal pure returns (uint256 z) {
        z = (x * baseUnit) / y;
    }


}
