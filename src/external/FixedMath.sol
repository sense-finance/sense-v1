// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

/// @title Fixed point arithmetic library
/// @author Taken from https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WDiv.sol & https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WMul.sol
library FixedMath {
    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/FixedMath.sol
    /// @dev Multiply an amount by a fixed point factor with 18 decimals, rounds down
    function fmul(
        uint256 x,
        uint256 y,
        uint256 baseUnit
    ) internal pure returns (uint256 z) {
        z = x * y;
        unchecked {
            z /= baseUnit;
        }
    }

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/FixedMath.sol
    /// @dev Divide an amount by a fixed point factor with 18 decimals, rounds down
    function fdiv(
        uint256 x,
        uint256 y,
        uint256 baseUnit
    ) internal pure returns (uint256 z) {
        z = (x * baseUnit) / y;
    }
}
