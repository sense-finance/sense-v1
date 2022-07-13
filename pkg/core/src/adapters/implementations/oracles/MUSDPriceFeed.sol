// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// Internal references
import { IPriceFeed } from "./IPriceFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

interface ChainlinkOracleLike {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface FeederPoolLike {
    function getPrice() external view returns (uint256 price, uint256 k);
}

/// @notice mStable Price feed

contract MUSDPriceFeed is IPriceFeed {
    using FixedMath for uint256;

    address public constant MUSD_ETH_POOL = 0x2F1423D27f9B20058d9D1843E342726fDF985Eb4; // mUSD-FEI Feeder pool
    address public constant FEI_ETH_PRICEFEED = 0x7F0D2c2838c6AC24443d13e23d99490017bDe370; // Chainlink FEI-ETH price feed

    function price() external view returns (uint256 price, uint256 updatedAt) {
        (price, ) = FeederPoolLike(MUSD_ETH_POOL).getPrice(); // Get Underlying-FEI price from mStable Feeder Pool // TODO: is this the best place to get the price?
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = ChainlinkOracleLike(FEI_ETH_PRICEFEED).latestRoundData(); // Get FEI-ETH price from Chainlink
        if (block.timestamp - ethUpdatedAt > 6 hours) revert Errors.InvalidPrice(); // FEI-ETH price feed updates every 2 hours approx

        // Calculate Underlying-ETH price
        price = uint256(ethPrice).fdiv(price);
        if (price < 0) revert Errors.InvalidPrice();
        return (price, ethUpdatedAt); // We return the updated timestamp from ETH-USD price feed since we don't have one for Underlying-USD
    }
}
