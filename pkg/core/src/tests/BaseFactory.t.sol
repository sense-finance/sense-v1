// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

contract Factories is TestHelper {
    function testDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        MockFactory someFactory = new MockFactory(address(divider), factoryParams, rewardTokens);

        assertTrue(address(someFactory) != address(0));
        assertEq(MockFactory(someFactory).divider(), address(divider));
        (
            address oracle,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint16 mode,
            uint64 tilt
        ) = MockFactory(someFactory).factoryParams();

        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(tilt, 0);
    }

    function testDeployAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someUnderlying = new MockToken("Some Underlying", "SR", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(someReward);
        MockFactory someFactory = createFactory(address(someTarget), rewardTokens);
        divider.setPeriphery(address(this));
        address adapter = someFactory.deployAdapter(address(someTarget));
        assertTrue(adapter != address(0));
        assertEq(MockAdapter(adapter).divider(), address(divider));
        assertEq(MockAdapter(adapter).target(), address(someTarget));
        assertEq(MockAdapter(adapter).name(), "Some Target Adapter");
        assertEq(MockAdapter(adapter).symbol(), "ST-adapter");
        assertEq(MockAdapter(adapter).stake(), address(stake));
        assertEq(MockAdapter(adapter).ifee(), ISSUANCE_FEE);
        assertEq(MockAdapter(adapter).stakeSize(), STAKE_SIZE);
        assertEq(MockAdapter(adapter).minm(), MIN_MATURITY);
        assertEq(MockAdapter(adapter).maxm(), MAX_MATURITY);
        assertEq(MockAdapter(adapter).oracle(), ORACLE);
        assertEq(MockAdapter(adapter).mode(), MODE);
        assertEq(MockAdapter(adapter).rewardTokens(0), address(someReward));
        uint256 scale = MockAdapter(adapter).scale();
        assertEq(scale, 1e18);
    }

    function testDeployAdapterAndinitializeSeries() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(someReward);
        MockFactory someFactory = createFactory(address(someTarget), rewardTokens);
        address f = periphery.deployAdapter(address(someFactory), address(someTarget));
        assertTrue(f != address(0));
        uint256 scale = MockAdapter(f).scale();
        assertEq(scale, 1e18);
        hevm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);
        (address principal, address yield) = alice.doSponsorSeries(f, maturity);
        assertTrue(principal != address(0));
        assertTrue(yield != address(0));
    }

    function testCantDeployAdapterIfNotPeriphery() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        factory.addTarget(address(someTarget), true);
        try factory.deployAdapter(address(someTarget)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.OnlyPeriphery.selector));
        }
    }

    function testFailDeployAdapterIfAlreadyExists() public {
        divider.setPeriphery(address(this));
        factory.deployAdapter(address(target));
    }
}
