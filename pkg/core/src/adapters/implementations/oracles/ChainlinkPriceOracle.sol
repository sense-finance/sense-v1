// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
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
/// @author Inspired on: https://github.com/Rari-Capital/fuse-contracts/blob/master/contracts/oracles/.sol
contract ChainlinkPriceOracle is IPriceFeed, Trust {
    using FixedMath for uint256;

    // Chainlink's denominations
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    address public constant USD = address(840);

    // The maxmimum number of seconds elapsed since the round was last updated before the price is considered stale. If set to 0, no limit is enforced.
    uint256 public maxSecondsBeforePriceIsStale;

    FeedRegistryLike feedRegistry = FeedRegistryLike(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf); // Chainlink feed registry contract

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
            if (maxSecondsBeforePriceIsStale > 0 && block.timestamp <= updatedAt + maxSecondsBeforePriceIsStale)
                revert Errors.StalePrice();
            if (tokenEthPrice <= 0) return 0;
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
            if (maxSecondsBeforePriceIsStale > 0 && block.timestamp <= updatedAt + maxSecondsBeforePriceIsStale)
                revert Errors.StalePrice();
            if (tokenUsdPrice <= 0) return 0;
            int256 ethUsdPrice;
            (, ethUsdPrice, , updatedAt, ) = feedRegistry.latestRoundData(ETH, USD);
            if (maxSecondsBeforePriceIsStale > 0 && block.timestamp <= updatedAt + maxSecondsBeforePriceIsStale)
                revert Errors.StalePrice();
            if (ethUsdPrice <= 0) return 0;
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
            if (maxSecondsBeforePriceIsStale > 0 && block.timestamp <= updatedAt + maxSecondsBeforePriceIsStale)
                revert Errors.StalePrice();
            if (tokenBtcPrice <= 0) return 0;
            int256 btcEthPrice;
            (, btcEthPrice, , updatedAt, ) = feedRegistry.latestRoundData(BTC, ETH);
            if (maxSecondsBeforePriceIsStale > 0 && block.timestamp <= updatedAt + maxSecondsBeforePriceIsStale)
                revert Errors.StalePrice();
            if (btcEthPrice <= 0) return 0;
            return
                uint256(tokenBtcPrice).fmul(uint256(btcEthPrice)).fdiv(
                    10**uint256(feedRegistry.decimals(underlying, BTC))
                );
        } catch Error(string memory reason) {
            if (keccak256(abi.encodePacked(reason)) != keccak256(abi.encodePacked("Feed not found")))
                revert Errors.AttemptFailed();
        }

        // Revert if all else fails
        revert("No Chainlink price feed found for this underlying ERC20 token.");
    }

    /// @dev Returns the price in ETH of `underlying` (implements `BasePriceOracle`).
    function price(address underlying) external view override returns (uint256) {
        return _price(underlying);
    }

    /// @dev Sets the `maxSecondsBeforePriceIsStale`.
    function setMaxSecondsBeforePriceIsStale(uint256 _maxSecondsBeforePriceIsStale) public requiresTrust {
        maxSecondsBeforePriceIsStale = _maxSecondsBeforePriceIsStale;
    }
}
