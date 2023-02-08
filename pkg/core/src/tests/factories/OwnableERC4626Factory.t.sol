// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { AutoRollerFactory } from "@auto-roller/src/AutoRollerFactory.sol";
import { AutoRoller, RollerUtils, DividerLike, OwnedAdapterLike } from "@auto-roller/src/AutoRoller.sol";
import { RollerPeriphery } from "@auto-roller/src/RollerPeriphery.sol";
import { OwnableERC4626Factory } from "../../adapters/abstract/factories/OwnableERC4626Factory.sol";
import { OwnableERC4626CropFactory } from "../../adapters/abstract/factories/OwnableERC4626CropFactory.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";

import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { MockAdapter, MockCropAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockToken, MockNonERC20Token } from "../test-helpers/mocks/MockToken.sol";
import { MockERC4626 } from "../test-helpers/mocks/MockERC4626.sol";

import { MockTarget, MockNonERC20Target } from "../test-helpers/mocks/MockTarget.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";

contract OwnableERC4626FactoryTest is TestHelper {
    address public constant RLV_FACTORY = address(0x1);
    OwnableERC4626Factory public oFactory;
    OwnableERC4626CropFactory public oCropFactory;

    function setUp() public override {
        is4626Target = true;
        super.setUp();

        _deployFactory();
        _deployCropFactory();
    }

    function _deployFactory() internal {
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
        oFactory = new OwnableERC4626Factory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );
        oFactory.supportTarget(address(target), true);
        divider.setIsTrusted(address(oFactory), true);
        periphery.setFactory(address(oFactory), true);

        assertTrue(address(oFactory) != address(0));
        assertEq(oFactory.divider(), address(divider));
        assertEq(oFactory.restrictedAdmin(), Constants.RESTRICTED_ADMIN);
        assertEq(oFactory.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(oFactory.rlvFactory(), RLV_FACTORY);

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

    function _deployCropFactory() internal {
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
        oCropFactory = new OwnableERC4626CropFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            RLV_FACTORY
        );
        oCropFactory.supportTarget(address(target), true);
        divider.setIsTrusted(address(oCropFactory), true);
        periphery.setFactory(address(oCropFactory), true);

        assertTrue(address(oCropFactory) != address(0));
        assertEq(oCropFactory.divider(), address(divider));
        assertEq(oCropFactory.restrictedAdmin(), Constants.RESTRICTED_ADMIN);
        assertEq(oCropFactory.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(oCropFactory.rlvFactory(), RLV_FACTORY);

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
        ) = OwnableERC4626CropFactory(oCropFactory).factoryParams();

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

    function testDeployOwnableERC4626CropAdapter() public {
        // Deploy ownable adapter
        vm.prank(address(periphery));
        address adapter = oCropFactory.deployAdapter(address(target), abi.encode(AddressBook.DAI));
        assertTrue(adapter != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = MockCropAdapter(adapter)
            .adapterParams();
        assertEq(MockCropAdapter(adapter).divider(), address(divider));
        assertEq(MockCropAdapter(adapter).target(), address(target));
        assertEq(MockCropAdapter(adapter).name(), "Compound Dai Adapter");
        assertEq(MockCropAdapter(adapter).symbol(), "cDAI-adapter");
        assertEq(MockCropAdapter(adapter).ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(MockCropAdapter(adapter).mode(), MODE);
        uint256 scale = MockCropAdapter(adapter).scale();
        assertEq(scale, 1e18);

        // Check ownable factory is trusted on the RLV adapter
        assertTrue(MockCropAdapter(adapter).isTrusted(RLV_FACTORY));

        // Check adapter has reward
        assertEq(MockCropAdapter(adapter).reward(), AddressBook.DAI);
    }

    function testFactoryWithRollerFactory() public {
        MockERC4626 someTarget = new MockERC4626(underlying, "Some Target", "ST", MockToken(underlying).decimals());
        if (nonERC20Underlying) {
            MockNonERC20Token(address(underlying)).approve(address(someTarget), type(uint256).max);
        } else {
            underlying.approve(address(someTarget), type(uint256).max);
        }
        someTarget.mint(10**tDecimals, address(this));

        // Deploy an Auto Roller Factory
        RollerUtils utils = new RollerUtils(address(divider));
        RollerPeriphery rollerPeriphery = new RollerPeriphery();
        AutoRollerFactory arFactory = new AutoRollerFactory(
            DividerLike(address(divider)),
            address(balancerVault),
            address(periphery),
            address(rollerPeriphery),
            utils
        );

        // Set AutoRollerFactory as trusted address on RollerPeriphery to be able to use the approve() function
        rollerPeriphery.setIsTrusted(address(arFactory), true);

        // Support target on oFactory
        oFactory.supportTarget(address(someTarget), true);

        // Change oFactory to use newly deployed arFactory
        oFactory.setRlvFactory(address(arFactory));

        // Deploy Ownable ERC4626 Adapter (oAdapter) for Auto Roller using oFactory
        address oAdapter = periphery.deployAdapter(address(oFactory), address(someTarget), "");

        // Deploy an autoroller
        AutoRoller autoRoller = arFactory.create(
            OwnedAdapterLike(address(oAdapter)),
            Constants.REWARDS_RECIPIENT,
            3 // target duration
        );

        // Approve Target & Stake
        if (nonERC20Target) {
            MockNonERC20Target(address(someTarget)).approve(address(autoRoller), 2 * 10**tDecimals);
        } else {
            someTarget.approve(address(autoRoller), 2 * 10**tDecimals);
        }
        if (nonERC20Stake) {
            MockNonERC20Token(address(stake)).approve(address(autoRoller), 10**tDecimals);
        } else {
            stake.approve(address(autoRoller), 10**sDecimals);
        }

        // Check we can make deposit.
        autoRoller.deposit(5 * 10**(tDecimals - 2), address(this)); // deposit 0.05
    }

    function testCanModifyRLVFactory() public {
        vm.record();

        // 1. Can't modify RLV factory if not owner
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x4b1d));
        oFactory.setRlvFactory(address(0xfede));
        assertEq(oFactory.rlvFactory(), RLV_FACTORY);

        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x4b1d));
        oCropFactory.setRlvFactory(address(0xfede));
        assertEq(oCropFactory.rlvFactory(), RLV_FACTORY);

        // 2. Can modify RLV factory if owner
        oFactory.setRlvFactory(address(0xfede));
        assertEq(oFactory.rlvFactory(), address(0xfede));

        oCropFactory.setRlvFactory(address(0xfede));
        assertEq(oCropFactory.rlvFactory(), address(0xfede));

        (, bytes32[] memory writes) = vm.accesses(address(oFactory));
        // Check only 1 storage slot was written
        assertEq(writes.length, 1);

        (, writes) = vm.accesses(address(oCropFactory));
        // Check only 1 storage slot was written
        assertEq(writes.length, 1);
    }
}
