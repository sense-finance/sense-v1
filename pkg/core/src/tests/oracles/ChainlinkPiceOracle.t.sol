// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

// Internal references
import { ChainlinkPriceOracle, FeedRegistryLike } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockChainlinkPriceOracle, MockFeedRegistry } from "../test-helpers/mocks/MockChainlinkPriceOracle.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

contract ChainPriceOracleTestHelper is Test {
    using FixedMath for uint256;

    ChainlinkPriceOracle internal oracle;
    MockToken internal underlying;

    function setUp() public {
        // Deploy Chainlink price oracle
        oracle = new ChainlinkPriceOracle(0);
        underlying = new MockToken("Underlying Token", "UT", 18);
    }
}

contract ChainlinkPriceOracleTest is ChainPriceOracleTestHelper {
    using FixedMath for uint256;

    function testMainnetDeployOracle() public {
        ChainlinkPriceOracle otherOracle = new ChainlinkPriceOracle(12345);

        assertTrue(address(otherOracle) != address(0));
        assertEq(address(otherOracle.feedRegistry()), AddressBook.CHAINLINK_REGISTRY);
        assertEq(otherOracle.maxSecondsBeforePriceIsStale(), 12345);
    }

    function testPriceWithETH() public {
        // Deploy mocked Feed Registry
        MockFeedRegistry feedRegistry = new MockFeedRegistry();

        // Deploy mocked Chainlink price oracle
        MockChainlinkPriceOracle oracle = new MockChainlinkPriceOracle(feedRegistry);

        // WETH price is 1e18
        assertEq(oracle.price(AddressBook.WETH), 1e18);

        // Token/ETH pair exists

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Mock call to Chainlink's oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(1, int256(price), block.timestamp, block.timestamp, 1); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.ETH()),
            data
        );
        assertEq(oracle.price(address(underlying)), price);
    }

    function testPriceWithUSD() public {
        // Deploy mocked Feed Registry
        MockFeedRegistry feedRegistry = new MockFeedRegistry();

        // Deploy mocked Chainlink price oracle
        MockChainlinkPriceOracle oracle = new MockChainlinkPriceOracle(feedRegistry);

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Token/ETH pair does not exist but Token/USD exists
        feedRegistry.setRevert(address(underlying), oracle.ETH(), "Feed not found");

        // Mock call to Token/USD Chainlink's oracle
        uint256 underUsdPrice = 456e18;
        bytes memory data = abi.encode(1, int256(underUsdPrice), block.timestamp, block.timestamp, 1); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.USD()),
            data
        );

        // Mock call to ETH/USD Chainlink's oracle
        uint256 ethUsdPrice = 789e18;
        data = abi.encode(1, int256(ethUsdPrice), block.timestamp, block.timestamp, 1); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, oracle.ETH(), oracle.USD()),
            data
        );
        assertEq(oracle.price(address(underlying)), underUsdPrice.fmul(1e26).fdiv(1e18).fdiv(ethUsdPrice));
    }

    function testPriceWithBTC() public {
        // Deploy mocked Feed Registry
        MockFeedRegistry feedRegistry = new MockFeedRegistry();

        // Deploy mocked Chainlink price oracle
        MockChainlinkPriceOracle oracle = new MockChainlinkPriceOracle(feedRegistry);

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Both Token/ETH and Token/USD pairs do not exist but Token/BTC exists
        feedRegistry.setRevert(address(underlying), oracle.ETH(), "Feed not found");
        feedRegistry.setRevert(address(underlying), oracle.USD(), "Feed not found");

        // Mock call to Token/BTC Chainlink's oracle
        uint256 underBtcPrice = 456e18;
        bytes memory data = abi.encode(1, int256(underBtcPrice), block.timestamp, block.timestamp, 1); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.BTC()),
            data
        );

        // Mock call to BTC/USD Chainlink's oracle
        uint256 btcEthPrice = 789e18;
        data = abi.encode(1, int256(btcEthPrice), block.timestamp, block.timestamp, 1); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, oracle.BTC(), oracle.ETH()),
            data
        );
        assertEq(oracle.price(address(underlying)), underBtcPrice.fmul(btcEthPrice).fdiv(1e18));
    }

    function testPriceRevertsWhenNoPriceExists() public {
        // Deploy mocked Feed Registry
        MockFeedRegistry feedRegistry = new MockFeedRegistry();

        // Deploy mocked Chainlink price oracle
        MockChainlinkPriceOracle oracle = new MockChainlinkPriceOracle(feedRegistry);

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Both Token/ETH and Token/USD pairs do not exist but Token/BTC exists
        feedRegistry.setRevert(address(underlying), oracle.ETH(), "Feed not found");
        feedRegistry.setRevert(address(underlying), oracle.USD(), "Feed not found");
        feedRegistry.setRevert(address(underlying), oracle.BTC(), "Feed not found");

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleNotFound.selector));
        oracle.price(address(underlying));
    }

    function testPriceAttemptFailed() public {
        // Deploy mocked Feed Registry
        MockFeedRegistry feedRegistry = new MockFeedRegistry();

        // Deploy mocked Chainlink price oracle
        MockChainlinkPriceOracle oracle = new MockChainlinkPriceOracle(feedRegistry);

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Token/ETH returns an invalid message
        feedRegistry.setRevert(address(underlying), oracle.ETH(), "Test");

        vm.expectRevert(abi.encodeWithSelector(Errors.AttemptFailed.selector));
        oracle.price(address(underlying));
    }

    function testShouldRevertIfPriceIsStale() public {
        vm.warp(12345678);

        // Set max seconds before price is stale to 4 hours
        oracle.setMaxSecondsBeforePriceIsStale(4 hours);

        FeedRegistryLike feedRegistry = FeedRegistryLike(oracle.feedRegistry());

        // Mock calls to decimals()
        vm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Mock call to Chainlink's oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(
            1,
            int256(price),
            block.timestamp - 4 hours - 1 seconds,
            block.timestamp - 4 hours - 1 seconds,
            1
        ); // return data
        vm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.ETH()),
            data
        );
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidPrice.selector));
        oracle.price(address(underlying));
    }

    function testCantSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        vm.prank(address(123));
        vm.expectRevert("UNTRUSTED");
        oracle.setMaxSecondsBeforePriceIsStale(12345);
    }

    function testSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 0);
        oracle.setMaxSecondsBeforePriceIsStale(12345);
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 12345);
    }
}
