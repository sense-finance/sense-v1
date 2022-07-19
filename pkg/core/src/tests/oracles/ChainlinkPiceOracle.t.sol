// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { ChainlinkPriceOracle, FeedRegistryLike } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { DSTest } from "../test-helpers/test.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { AddressBook } from "../test-helpers/AddressBook.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Hevm } from "../test-helpers/Hevm.sol";

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
        hevm.etch(address(feedRegistry), hex"1010");

        // Token/ETH pair exists
        assertEq(oracle.price(AddressBook.WETH), 1e18);

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

    function testMainnetCantSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        hevm.prank(address(123));
        hevm.expectRevert("UNTRUSTED");
        oracle.setMaxSecondsBeforePriceIsStale(12345);
    }

    function testMainnetSetMaxSecondsBeforePriceIsStaleIfNotTrusted() public {
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 0);
        oracle.setMaxSecondsBeforePriceIsStale(12345);
        assertEq(oracle.maxSecondsBeforePriceIsStale(), 12345);
    }
}
