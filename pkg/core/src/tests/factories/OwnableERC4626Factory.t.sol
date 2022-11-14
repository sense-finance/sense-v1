// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import { AutoRollerFactory } from "@auto-roller/src/AutoRollerFactory.sol";
import { AutoRoller, RollerUtils, DividerLike, OwnedAdapterLike } from "@auto-roller/src/AutoRoller.sol";
import { RollerPeriphery } from "@auto-roller/src/RollerPeriphery.sol";
import { OwnableERC4626Factory } from "../../adapters/abstract/factories/OwnableERC4626Factory.sol";
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

contract OwnableERC4626FactoryTest is TestHelper {
    address public constant RLV_FACTORY = address(0x1);

    function setUp() public override {
        is4626Target = true;
        super.setUp();
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
        OwnableERC4626Factory oFactory = new OwnableERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );

        assertTrue(address(oFactory) != address(0));
        assertEq(OwnableERC4626Factory(oFactory).divider(), address(divider));
        assertEq(OwnableERC4626Factory(oFactory).restrictedAdmin(), Constants.RESTRICTED_ADMIN);
        assertEq(OwnableERC4626Factory(oFactory).rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(OwnableERC4626Factory(oFactory).rlvFactory(), RLV_FACTORY);

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
        ) = OwnableERC4626Factory(oFactory).factoryParams();

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

    function testDeployOwnableERC4626Adapter() public {
        // Deploy Ownable ERC4626 factory (oFactory)
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
        OwnableERC4626Factory oFactory = new OwnableERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );
        oFactory.supportTarget(address(target), true);
        divider.setIsTrusted(address(oFactory), true);
        periphery.setFactory(address(oFactory), true);

        // Deploy ownable adapter
        vm.prank(address(periphery));
        address adapter = oFactory.deployAdapter(address(target), "");
        assertTrue(adapter != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = MockAdapter(adapter)
            .adapterParams();
        assertEq(MockAdapter(adapter).divider(), address(divider));
        assertEq(MockAdapter(adapter).target(), address(target));
        assertEq(MockAdapter(adapter).name(), "Compound Dai Adapter");
        assertEq(MockAdapter(adapter).symbol(), "cDAI-adapter");
        assertEq(MockAdapter(adapter).ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(MockAdapter(adapter).mode(), MODE);
        uint256 scale = MockAdapter(adapter).scale();
        assertEq(scale, 1e18);

        // Check ownable factory is trusted on the RLV adapter
        assertTrue(MockAdapter(adapter).isTrusted(RLV_FACTORY));
    }

    function testFactoryWithRollerFactory() public {
        MockERC4626 someTarget = new MockERC4626(underlying, "Some Target", "ST", MockToken(underlying).decimals());
        someTarget.mint(1e18, address(this));

        // Deploy an Auto Roller
        RollerUtils utils = new RollerUtils();
        RollerPeriphery rollerPeriphery = new RollerPeriphery();
        AutoRollerFactory arFactory = new AutoRollerFactory(
            DividerLike(address(divider)),
            address(balancerVault),
            address(periphery),
            address(rollerPeriphery),
            utils,
            type(AutoRoller).creationCode
        );

        // Deploy Ownable ERC4626 factory (oFactory)
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
        OwnableERC4626Factory oFactory = new OwnableERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            address(arFactory)
        );
        oFactory.supportTarget(address(someTarget), true);
        divider.setIsTrusted(address(oFactory), true);
        periphery.setFactory(address(oFactory), true);

        // Deploy Ownable ERC4626 Adapter (oAdapter) for Auto Roller using oFactory
        address oAdapter = periphery.deployAdapter(address(oFactory), address(someTarget), "");

        // Deploy an autoroller
        AutoRoller autoRoller = arFactory.create(
            OwnedAdapterLike(address(oAdapter)),
            Constants.REWARDS_RECIPIENT,
            3 // target duration
        );

        // Approve Target & Stake
        target.approve(address(autoRoller), 2e18);
        stake.approve(address(autoRoller), 1e18);

        // Check we can make deposit.
        autoRoller.deposit(0.05e18, address(this));
    }

    function testCanModifyRLVFactory() public {
        // Deploy Ownable ERC4626 factory (oFactory)
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
        OwnableERC4626Factory oFactory = new OwnableERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );

        vm.record();

        // 1. Can't modify RLV factory if not owner
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x4b1d));
        oFactory.setRlvFactory(address(0xfede));
        assertEq(oFactory.rlvFactory(), RLV_FACTORY);

        // 2. Can modify RLV factory if owner
        oFactory.setRlvFactory(address(0xfede));
        assertEq(oFactory.rlvFactory(), address(0xfede));

        (, bytes32[] memory writes) = vm.accesses(address(oFactory));
        // Check only 1 storage slot was written
        assertEq(writes.length,1);
    }
}
