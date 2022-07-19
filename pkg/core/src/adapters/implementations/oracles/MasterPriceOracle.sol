// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { IPriceFeed } from "../../abstract/IPriceFeed.sol";

/// @notice This contract gets prices from an available oracle address which must implement IPriceFeed.sol
/// If there's no oracle set, it will try getting the price from Chainlink's Oracle.
/// @author Inspired on: https://github.com/Rari-Capital/fuse-contracts/blob/master/contracts/oracles/MasterPriceOracle.sol
contract MasterPriceOracle is IPriceFeed, Trust {
    address public immutable SENSE_CHAINLINK_PRICE_FEED;

    /// @dev Maps underlying token addresses to `PriceOracle` contracts (can be `BasePriceOracle` contracts too).
    mapping(address => address) public oracles; // TODO: use IPriceFeed.sol?

    /// @dev Constructor to initialize state variables.
    /// @param _chainlinkOracle The underlying ERC20 token addresses to link to `_oracles`.
    /// @param _underlyings The underlying ERC20 token addresses to link to `_oracles`.
    /// @param _oracles The `PriceOracle` contracts to be assigned to `underlyings`.
    constructor(
        address _chainlinkOracle,
        address[] memory _underlyings,
        address[] memory _oracles
    ) public Trust(msg.sender) {
        SENSE_CHAINLINK_PRICE_FEED = _chainlinkOracle;

        // Input validation
        if (_underlyings.length != _oracles.length) revert Errors.InvalidParam();

        // Initialize state variables
        for (uint256 i = 0; i < _underlyings.length; i++) oracles[_underlyings[i]] = _oracles[i];
    }

    /// @dev Sets `_oracles` for `underlyings`.
    /// Caller of this function must make sure that the oracles being added return non-stale, greater than 0
    /// prices for all underlying tokens.
    function add(address[] calldata _underlyings, address[] calldata _oracles) external requiresTrust {
        if (_underlyings.length <= 0 || _underlyings.length != _oracles.length) revert Errors.InvalidParam();

        for (uint256 i = 0; i < _underlyings.length; i++) {
            oracles[_underlyings[i]] = _oracles[i];
        }
    }

    /// @dev Attempts to return the price in ETH of `underlying` (implements `BasePriceOracle`).
    function price(address underlying) external view override returns (uint256) {
        if (underlying == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return 1e18; // Return 1e18 for WETH

        address oracle = oracles[underlying];
        if (oracle != address(0)) {
            return IPriceFeed(oracle).price(underlying);
        } else {
            // Try token/ETH from Sense's Chainlink Oracle
            try IPriceFeed(SENSE_CHAINLINK_PRICE_FEED).price(underlying) returns (uint256 price) {
                return price;
            } catch {
                revert Errors.PriceOracleNotFound();
            }
        }
    }
}
