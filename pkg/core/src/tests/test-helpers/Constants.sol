// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

/// @notice System constants
library Constants {
    // adapter config
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant DEFAULT_STAKE_SIZE = 1e18;
    uint256 public constant DEFAULT_MIN_MATURITY = 2 weeks;
    uint256 public constant DEFAULT_MAX_MATURITY = 14 weeks;
    uint16 public constant DEFAULT_DEFAULT_LEVEL = 31;
    uint16 public constant DEFAULT_TILT = 0;
    uint16 public constant DEFAULT_MODE = 0;
    uint64 public constant DEFAULT_ISSUANCE_FEE = 0.05e18;
    uint256 public constant DEFAULT_GUARD = 100000 * 1e18;
    uint256 public constant DEFAULT_CHAINLINK_ETH_PRICE = 1900 * 1e8; // $1900 per ETH
}
