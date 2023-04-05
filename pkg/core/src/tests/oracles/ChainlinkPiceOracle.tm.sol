// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

interface FeedLike {
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

    function decimals() external view returns (uint8);
}

contract ChainPriceOracleTestHelper is ForkTest {
    using FixedMath for uint256;

    ChainlinkPriceOracle internal oracle;

    address public constant CHAINLINK_DAI_ORACLE = 0x773616E4d11A78F511299002da57A0a94577F1f4; // DAI/ETH
    address public constant CHAINLINK_FXS_ORACLE = 0x6Ebc52C8C1089be9eB3945C4350B68B8E4C2233f; // FXS/USD
    address public constant CHAINLINK_WBTC_ORACLE = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23; // WBTC/BTC
    address public constant CHAINLINK_ETH_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD
    address public constant CHAINLINK_BTC_ORACLE = 0xdeb288F737066589598e9214E782fa5A8eD689e8; // BTC/ETH

    function setUp() public {
        fork();
        // Deploy Chainlink price oracle
        oracle = new ChainlinkPriceOracle(0);
    }
}

contract ChainlinkPriceOracles is ChainPriceOracleTestHelper {
    using FixedMath for uint256;

    function testMainnetDeployOracle() public {
        ChainlinkPriceOracle otherOracle = new ChainlinkPriceOracle(12345);

        assertTrue(address(otherOracle) != address(0));
        assertEq(address(otherOracle.feedRegistry()), AddressBook.CHAINLINK_REGISTRY);
        assertEq(otherOracle.maxSecondsBeforePriceIsStale(), 12345);
    }

    function testMainnetPrice() public {
        // WETH price is 1e18
        assertEq(oracle.price(AddressBook.WETH), 1e18);

        // Token/ETH pair exists
        (, int256 daiEthPrice, , , ) = FeedLike(CHAINLINK_DAI_ORACLE).latestRoundData();
        assertEq(oracle.price(AddressBook.DAI), uint256(daiEthPrice));

        // Token/ETH pair does not exists but Token/USD does
        (, int256 htUsdPrice, , , ) = FeedLike(CHAINLINK_FXS_ORACLE).latestRoundData();
        (, int256 ethUsdPrice, , , ) = FeedLike(CHAINLINK_ETH_ORACLE).latestRoundData();
        uint256 price = uint256(htUsdPrice).fmul(1e26).fdiv(10**FeedLike(CHAINLINK_FXS_ORACLE).decimals()).fdiv(
            uint256(ethUsdPrice)
        );
        assertEq(oracle.price(AddressBook.FXS), price);

        // Neither Token/ETH nor Token/USD pair exist but Token/BTC does
        (, int256 wBtcBtcPrice, , , ) = FeedLike(CHAINLINK_WBTC_ORACLE).latestRoundData();
        (, int256 btcEthPrice, , , ) = FeedLike(CHAINLINK_BTC_ORACLE).latestRoundData();
        price = uint256(wBtcBtcPrice).fmul(uint256(btcEthPrice)).fdiv(10**FeedLike(CHAINLINK_WBTC_ORACLE).decimals());
        assertEq(oracle.price(AddressBook.WBTC), price);
    }
}
