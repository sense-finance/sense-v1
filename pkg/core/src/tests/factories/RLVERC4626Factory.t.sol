// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import { RLVERC4626Factory } from "../../adapters/abstract/factories/RLVERC4626Factory.sol";
// import { ERC4626CropsAdapter } from "../../adapters/abstract/erc4626/ERC4626CropsAdapter.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";

import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { MockAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockERC4626 } from "../test-helpers/mocks/MockERC4626.sol";

import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";

contract RLVERC4626FactoryTest is TestHelper {
    address public constant RLV_FACTORY = address(0x1);

    function setUp() public override {
        super.setUp();
        is4626Target = true;
    }

    function testDeployFactory() public {
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: 123e18
        });
        RLVERC4626Factory someFactory = new RLVERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );

        assertTrue(address(someFactory) != address(0));
        assertEq(RLVERC4626Factory(someFactory).divider(), address(divider));
        assertEq(RLVERC4626Factory(someFactory).restrictedAdmin(), Constants.RESTRICTED_ADMIN);
        assertEq(RLVERC4626Factory(someFactory).rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(RLVERC4626Factory(someFactory).rlvFactory(), RLV_FACTORY);

        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint256 ifee,
            uint16 mode,
            uint64 tilt,
            uint256 guard
        ) = RLVERC4626Factory(someFactory).factoryParams();

        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(tilt, 0);
        assertEq(guard, 123e18);
    }

    function testDeployRLVERC4626Adapter() public {
        MockERC4626 someTarget = new MockERC4626(underlying, "Some Target", "ST", MockToken(underlying).decimals());

        // Deploy RLV ERC4626 non-crops factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            guard: 123e18
        });
        RLVERC4626Factory someFactory = new RLVERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );
        someFactory.supportTarget(address(someTarget), true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);

        // Deploy RLV non-crops adapter
        vm.prank(address(periphery));
        address adapter = someFactory.deployAdapter(address(someTarget), "");
        assertTrue(adapter != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = MockAdapter(adapter)
            .adapterParams();
        assertEq(MockAdapter(adapter).divider(), address(divider));
        assertEq(MockAdapter(adapter).target(), address(someTarget));
        assertEq(MockAdapter(adapter).name(), "Some Target Adapter");
        assertEq(MockAdapter(adapter).symbol(), "ST-adapter");
        assertEq(MockAdapter(adapter).ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(MockAdapter(adapter).mode(), MODE);
        uint256 scale = MockAdapter(adapter).scale();
        assertEq(scale, 1e18);

        // Check RLV factoyr is trusted on the RLV adapter
        assertTrue(MockAdapter(adapter).isTrusted(RLV_FACTORY));
    }
}
