// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Testing utils
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { MockDividerSpace, MockAdapterSpace, ERC20Mintable } from "./utils/Mocks.sol";
import { VM } from "./utils/VM.sol";

// External references
import { Vault, IVault, IWETH } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";

// Internal references
import { SpaceFactory } from "../SpaceFactory.sol";
import { Space } from "../Space.sol";

contract SpaceFactoryTest is DSTest {
    using FixedPoint for uint256;

    VM internal constant vm = VM(HEVM_ADDRESS);
    IWETH internal constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Vault internal vault;
    SpaceFactory internal spaceFactory;
    MockDividerSpace internal divider;
    MockAdapterSpace internal adapter;
    uint48 internal maturity1;
    uint48 internal maturity2;
    uint48 internal maturity3;

    uint256 internal ts;
    uint256 internal g1;
    uint256 internal g2;

    function setUp() public {
        // Init normalized starting conditions
        vm.warp(0);
        vm.roll(0);

        // Create mocks
        divider = new MockDividerSpace(18);
        adapter = new MockAdapterSpace(18);

        ts = FixedPoint.ONE.divDown(FixedPoint.ONE * 31622400); // 1 / 1 year in seconds
        // 0.95 for selling underlying
        g1 = (FixedPoint.ONE * 950).divDown(FixedPoint.ONE * 1000);
        // 1 / 0.95 for selling Zeros
        g2 = (FixedPoint.ONE * 1000).divDown(FixedPoint.ONE * 950);

        maturity1 = 15811200; // 6 months in seconds
        maturity2 = 31560000; // 1 yarn in seconds
        maturity3 = 63120000; // 2 years in seconds

        Authorizer authorizer = new Authorizer(address(this));
        vault = new Vault(authorizer, weth, 0, 0);
        spaceFactory = new SpaceFactory(vault, address(divider), ts, g1, g2);
    }

    function testCreatePool() public {
        address space = spaceFactory.create(address(adapter), maturity1);

        assertTrue(space != address(0));
        assertEq(space, spaceFactory.pools(address(adapter), maturity1));

        try spaceFactory.create(address(adapter), maturity1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "POOL_ALREADY_EXISTS");
        }
    }

    function testSetParams() public {
        Space space = Space(spaceFactory.create(address(adapter), maturity1));

        // Sanity check that params set in constructor are used
        assertEq(space.ts(), ts);
        assertEq(space.g1(), g1);
        assertEq(space.g2(), g2);

        ts = FixedPoint.ONE.divDown(FixedPoint.ONE * 100);
        g1 = (FixedPoint.ONE * 900).divDown(FixedPoint.ONE * 1000);
        g2 = (FixedPoint.ONE * 1000).divDown(FixedPoint.ONE * 900);
        spaceFactory.setParams(ts, g1, g2);
        space = Space(spaceFactory.create(address(adapter), maturity2));

        // If params are updated, the new ones are used in the next deployment
        assertEq(space.ts(), ts);
        assertEq(space.g1(), g1);
        assertEq(space.g2(), g2);

        // Fee params are validated
        g1 = (FixedPoint.ONE * 1000).divDown(FixedPoint.ONE * 900);
        try spaceFactory.setParams(ts, g1, g2) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "INVALID_G1");
        }
        g1 = (FixedPoint.ONE * 900).divDown(FixedPoint.ONE * 1000);
        g2 = (FixedPoint.ONE * 900).divDown(FixedPoint.ONE * 1000);
        try spaceFactory.setParams(ts, g1, g2) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "INVALID_G2");
        }
    }
}