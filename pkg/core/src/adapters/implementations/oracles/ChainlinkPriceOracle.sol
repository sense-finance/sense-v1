// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { IPriceFeed } from "../../abstract/IPriceFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

interface FeedRegistryLike {
    function latestRoundData(address base, address quote)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals(address base, address quote) external view returns (uint8);
}

/// @title ChainlinkPriceOracle
/// @notice Returns prices from Chainlink.
/// @dev Implements `IPricefeed` and `Trust`.
/// @author Inspired by: https://github.com/Rari-Capital/fuse-v1/blob/development/src/oracles/ChainlinkPriceOracleV3.sol
contract ChainlinkPriceOracle is IPriceFeed, Trust {
    using FixedMath for uint256;

    // Chainlink's denominations
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address public constant USD = address(840);

    // The maxmimum number of seconds elapsed since the round was last updated before the price is considered stale. If set to 0, no limit is enforced.
    uint256 public maxSecondsBeforePriceIsStale;

    FeedRegistryLike public feedRegistry = FeedRegistryLike(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf); // Chainlink feed registry contract

    constructor(uint256 _maxSecondsBeforePriceIsStale) public Trust(msg.sender) {
        maxSecondsBeforePriceIsStale = _maxSecondsBeforePriceIsStale;
    }

    /// @dev Internal function returning the price in ETH of `underlying`.
    function _price(address underlying) internal view returns (uint256) {
        // Return 1e18 for WETH
        if (underlying == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return 1e18;

        // Try token/ETH to get token/ETH
        try feedRegistry.latestRoundData(underlying, ETH) returns (
            uint80,
            int256 tokenEthPrice,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (tokenEthPrice <= 0) return 0;
            _validatePrice(updatedAt);
            return uint256(tokenEthPrice).fmul(1e18).fdiv(10**uint256(feedRegistry.decimals(underlying, ETH)));
        } catch Error(string memory reason) {
            if (keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Feed not found")))
                revert Errors.AttemptFailed();
        }

        // Try token/USD to get token/ETH
        try feedRegistry.latestRoundData(underlying, USD) returns (
            uint80,
            int256 tokenUsdPrice,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (tokenUsdPrice <= 0) return 0;
            _validatePrice(updatedAt);

            int256 ethUsdPrice;
            (, ethUsdPrice, , updatedAt, ) = feedRegistry.latestRoundData(ETH, USD);
            if (ethUsdPrice <= 0) return 0;
            _validatePrice(updatedAt);
            return
                uint256(tokenUsdPrice).fmul(1e26).fdiv(10**uint256(feedRegistry.decimals(underlying, USD))).fdiv(
                    uint256(ethUsdPrice)
                );
        } catch Error(string memory reason) {
            if (keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Feed not found")))
                revert Errors.AttemptFailed();
        }

        // Try token/BTC to get token/ETH
        try feedRegistry.latestRoundData(underlying, BTC) returns (
            uint80,
            int256 tokenBtcPrice,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (tokenBtcPrice <= 0) return 0;
            _validatePrice(updatedAt);

            int256 btcEthPrice;
            (, btcEthPrice, , updatedAt, ) = feedRegistry.latestRoundData(BTC, ETH);
            if (btcEthPrice <= 0) return 0;
            _validatePrice(updatedAt);

            return
                uint256(tokenBtcPrice).fmul(uint256(btcEthPrice)).fdiv(
                    10**uint256(feedRegistry.decimals(underlying, BTC))
                );
        } catch Error(string memory reason) {
            if (keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Feed not found")))
                revert Errors.AttemptFailed();
        }

        // Revert if all else fails
        revert Errors.PriceOracleNotFound();
    }

    /// @dev validates the price returned from Chainlink
    function _validatePrice(uint256 _updatedAt) internal view {
        if (maxSecondsBeforePriceIsStale > 0 && block.timestamp > _updatedAt + maxSecondsBeforePriceIsStale)
            revert Errors.InvalidPrice();
    }

    /// @dev Returns the price in ETH of `underlying` (implements `BasePriceOracle`).
    function price(address underlying) external view override returns (uint256) {
        return _price(underlying);
    }

    /// @dev Sets the `maxSecondsBeforePriceIsStale`.
    function setMaxSecondsBeforePriceIsStale(uint256 _maxSecondsBeforePriceIsStale) public requiresTrust {
        maxSecondsBeforePriceIsStale = _maxSecondsBeforePriceIsStale;
        emit MaxSecondsBeforePriceIsStaleChanged(maxSecondsBeforePriceIsStale);
    }

    /* ========== LOGS ========== */
    event MaxSecondsBeforePriceIsStaleChanged(uint256 indexed maxSecondsBeforePriceIsStale);
}
