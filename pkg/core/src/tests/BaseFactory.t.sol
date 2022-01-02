// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { IAdapter } from "./test-helpers/interfaces/IAdapter.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        MockAdapter adapterImpl = new MockAdapter();
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });
        MockFactory someFactory = new MockFactory(
            address(adapterImpl),
            address(divider),
            factoryParams,
            address(reward)
        );

        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).adapterImpl(), address(adapterImpl));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        (
            address oracle,
            uint256 delta,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint8 mode
        ) = MockFactory(someFactory).factoryParams();
        assertEq(oracle, ORACLE);
        assertEq(delta, DELTA);
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
    }

    function testDeployAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        address adapter = someFactory.deployAdapter(address(someTarget));
        assertTrue(adapter != address(0));
        (
            address target,
            address oracle,
            uint256 delta,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint8 mode
        ) = BaseAdapter(adapter).adapterParams();
        assertEq(IAdapter(adapter).divider(), address(divider));
        assertEq(target, address(someTarget));
        assertEq(delta, DELTA);
        assertEq(IAdapter(adapter).name(), "Some Target Adapter");
        assertEq(IAdapter(adapter).symbol(), "ST-adapter");
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(mode, MODE);
        uint256 scale = IAdapter(adapter).scale();
        assertEq(scale, 1e18);
    }

    function testDeployAdapterAndinitializeSeries() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        address f = periphery.onboardAdapter(address(someFactory), address(someTarget));
        assertTrue(f != address(0));
        uint256 scale = IAdapter(f).scale();
        assertEq(scale, 1e18);
        hevm.warp(block.timestamp + 1 days);
        uint48 maturity = uint48(DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0));
        (address zero, address claim) = alice.doSponsorSeries(f, maturity);
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));
    }

    function testCantDeployAdapterIfTargetIsNotSupported() public {
        MockToken newTarget = new MockToken("Not Supported", "NS", 18);
        try factory.deployAdapter(address(newTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
    }

    function testCantDeployAdapterIfTargetIsNotSupportedOnSpecificAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someTarget = new MockToken("Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        try factory.deployAdapter(address(someTarget)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotSupported);
        }
        someFactory.deployAdapter(address(someTarget));
    }

    function testCantDeployAdapterIfAlreadyExists() public {
        try factory.deployAdapter(address(target)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.Create2Failed);
        }
    }
}
