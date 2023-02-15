// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Utils is Test {
    function percentageToDecimal(uint128 percentageFee) public returns (uint128 decimal) {
        decimal = percentageFee / 100;
        emit log_named_decimal_uint("- Decimal: ", decimal, 18);
    }

    function decimalToPercentage(uint128 decimal) public returns (uint128 percentage) {
        percentage = decimal * 100;
        emit log_named_decimal_uint("- Percentage: ", percentage, 18);
    }

    function percentageToBps(uint128 percentageFee) public returns (uint128 bps) {
        bps = percentageFee * 100;
        emit log_named_decimal_uint("- BPS: ", bps, 18);
    }

    function BpsToPercentage(uint128 bps) public returns (uint128 percentage) {
        percentage = bps / 100;
        emit log_named_decimal_uint("- Percentage: ", percentage, 18);
    }
}
