// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { DSTest } from "../test-helpers/test.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract MasterPriceOracleTestHelper is DSTest {
    MasterPriceOracle internal oracle;
    ChainlinkPriceOracle internal chainlinkOracle;
    MockOracle internal mockOracle;
    MockToken internal underlying;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        // Deploy Sense Chainlink price oracle
        chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master price oracle
        address[] memory data;
        oracle = new MasterPriceOracle(address(chainlinkOracle), data, data);

        // Deploy mock oracle
        mockOracle = new MockOracle();

        // Deploy a mock token
        underlying = new MockToken("Underlying Token", "UT", 18);
    }
}

contract MockOracle is IPriceFeed {
    function price(address) external view returns (uint256 price) {
        return 555e18;
    }
}

contract MasterPriceOracleTest is MasterPriceOracleTestHelper {
    function testMainnetDeployOracle() public {
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(mockOracle);

        MasterPriceOracle otherOracle = new MasterPriceOracle(address(chainlinkOracle), underlyings, oracles);
        assertTrue(address(otherOracle) != address(0));
        assertEq(otherOracle.senseChainlinkPriceOracle(), address(chainlinkOracle));
        assertEq(otherOracle.oracles(address(underlying)), address(mockOracle));
    }

    function testPriceIfOracleDoesNotExists() public {
        hevm.expectRevert(abi.encodeWithSelector(Errors.PriceOracleNotFound.selector));
        oracle.price(address(underlying));
    }

    function testPriceIfOracleIsSet() public {
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(mockOracle);

        // add oracle fo underlying
        oracle.add(underlyings, oracles);
        assertEq(oracle.price(address(underlying)), 555e18);
    }

    function testPriceSenseChainlinkOracle() public {
        // Mock call to Chainlink's oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(price); // return data
        hevm.mockCall(
            address(chainlinkOracle),
            abi.encodeWithSelector(chainlinkOracle.price.selector, address(underlying)),
            data
        );
        assertEq(oracle.price(address(underlying)), price);
    }

    function testCantAddOracleIfNotTrusted() public {
        hevm.prank(address(123));
        hevm.expectRevert("UNTRUSTED");
        address[] memory data;
        oracle.add(data, data);
    }

    function testAddOracle() public {
        assertEq(oracle.oracles(address(underlying)), address(0));

        // add oracle for underlying
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle);

        oracle.add(underlyings, oracles);
        assertEq(oracle.oracles(address(underlying)), address(oracle));
    }

    function testCantSetNewChainlinkOracle() public {
        hevm.prank(address(123));
        hevm.expectRevert("UNTRUSTED");
        oracle.setSenseChainlinkPriceOracle(address(111));
    }

    function testSetNewChainlinkOracle() public {
        assertEq(oracle.senseChainlinkPriceOracle(), address(chainlinkOracle));
        oracle.setSenseChainlinkPriceOracle(address(123));
        assertEq(oracle.senseChainlinkPriceOracle(), address(123));
    }
}
