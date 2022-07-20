// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { ChainlinkPriceOracle, FeedRegistryLike } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { DSTest } from "../test-helpers/test.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { AddressBook } from "../test-helpers/AddressBook.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract ChainPriceOracleTestHelper is DSTest {
    using FixedMath for uint256;

    ChainlinkPriceOracle internal oracle;
    MockToken internal underlying;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

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

    function testPrice() public {
        FeedRegistryLike feedRegistry = FeedRegistryLike(oracle.feedRegistry());

        // WETH price is 1e18
        assertEq(oracle.price(AddressBook.WETH), 1e18);

        // Token/ETH pair exists

        // Mock calls to decimals()
        hevm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Mock call to Chainlink's oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(1, int256(price), block.timestamp, block.timestamp, 1); // return data
        hevm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.ETH()),
            data
        );
        assertEq(oracle.price(address(underlying)), price);
    }

    function testShouldRevertIfPriceIsStale() public {
        hevm.warp(12345678);

        // Set max seconds before price is stale to 4 hours
        oracle.setMaxSecondsBeforePriceIsStale(4 hours);

        FeedRegistryLike feedRegistry = FeedRegistryLike(oracle.feedRegistry());

        // Mock calls to decimals()
        hevm.mockCall(address(feedRegistry), abi.encodeWithSelector(feedRegistry.decimals.selector), abi.encode(18));

        // Mock call to Chainlink's oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(1, int256(price), block.timestamp - 4 hours, block.timestamp - 4 hours, 1); // return data
        hevm.mockCall(
            address(feedRegistry),
            abi.encodeWithSelector(feedRegistry.latestRoundData.selector, address(underlying), oracle.ETH()),
            data
        );
        hevm.expectRevert(abi.encodeWithSelector(Errors.StalePrice.selector));
        oracle.price(address(underlying));
    }

    function testCantSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        hevm.prank(address(123));
        hevm.expectRevert("UNTRUSTED");
        oracle.setMaxSecondsBeforePriceIsStale(12345);
    }

    function testSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 0);
        oracle.setMaxSecondsBeforePriceIsStale(12345);
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 12345);
    }
}
