pragma solidity 0.8.11;

/// @title Fixed point arithmetic library
/// @author Taken from https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WDiv.sol & https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/math/WMul.sol
library FixedMath {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant RAY = 1e27;

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Multiply an amount by a fixed point factor, rounds down
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

    function fmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        unchecked {
            z /= WAD;
        }
    }

    function fmulUp(
        uint256 x,
        uint256 y,
        uint256 baseUnit
    ) internal pure returns (uint256 z) {
        z = x * y + baseUnit - 1; // Rounds up.  So (again imagining 2 decimal places):
        unchecked {
            z /= (baseUnit);
        } // 383 (3.83) * 235 (2.35) -> 90005 (9.0005), + 99 (0.0099) -> 90104, / 100 -> 901 (9.01).
    }

    function fmulUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y + WAD - 1;
        unchecked {
            z /= (WAD);
        }
    }

    /// Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide an amount by a fixed point factor, rounds down
    function fdiv(
        uint256 x,
        uint256 y,
        uint256 baseUnit
    ) internal pure returns (uint256 z) {
        z = (x * baseUnit) / y;
    }

    function fdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * WAD) / y;
    }

    function fdivUp(
        uint256 x,
        uint256 y,
        uint256 baseUnit
    ) internal pure returns (uint256 z) {
        z = x * baseUnit + y; // 101 (1.01) / 1000 (10) -> (101 * 100 + 1000 - 1) / 1000 -> 11 (0.11 = 0.101 rounded up).
        unchecked {
            z -= 1;
        } // Can do unchecked subtraction since division in next line will catch y = 0 case anyway
        z /= y;
    }

    function fdivUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * WAD + y;
        unchecked {
            z -= 1;
        }
        z /= y;
    }
}
