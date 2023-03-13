// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { MockAdapter, MockCropAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockFactory, MockCropFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { ERC4626CropAdapter } from "../../adapters/abstract/erc4626/ERC4626CropAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { Bytes32AddressLib } from "solmate/utils/Bytes32AddressLib.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";
import { Periphery } from "../../Periphery.sol";

contract MockRevertAdapter is MockAdapter {
    constructor(BaseAdapter.AdapterParams memory _adapterParams)
        MockAdapter(address(0), address(0), address(0), address(0), 1, _adapterParams)
    {}

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        revert("ERROR");
    }
}

contract MockRevertFactory is MockFactory {
    constructor(BaseFactory.FactoryParams memory _factoryParams)
        MockFactory(address(0), address(0), address(0), _factoryParams)
    {}

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        BaseAdapter.AdapterParams memory adapterParams;
        adapter = address(new MockRevertAdapter(adapterParams));
        _setGuard(adapter);
    }
}

// Mock adapter with 2e18 initial scale value
contract Mock2e18Adapter is MockCropAdapter {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) MockCropAdapter(_divider, _target, _underlying, Constants.REWARDS_RECIPIENT, _ifee, _adapterParams, _reward) {
        INITIAL_VALUE = 2e18;
    }
}

contract Mock2e18Factory is MockCropFactory {
    using Bytes32AddressLib for address;

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams,
        address _reward
    ) MockCropFactory(_divider, _restrictedAdmin, _rewardsRecipient, _factoryParams, _reward) {}

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });
        adapter = address(
            new Mock2e18Adapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                MockTargetLike(_target).underlying(),
                factoryParams.ifee,
                adapterParams,
                reward
            )
        );
        _setGuard(adapter);
    }
}

contract Factories is TestHelper {
    using FixedMath for uint256;

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
        MockCropFactory someFactory = new MockCropFactory(
            address(divider),
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            address(reward)
        );

        assertEq(someFactory.restrictedAdmin(), Constants.RESTRICTED_ADMIN);
        assertEq(someFactory.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(someFactory.divider(), address(divider));
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
        ) = someFactory.factoryParams();

        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, MODE);
        assertEq(tilt, 0);
        assertEq(guard, 123e18);
        assertEq(someFactory.reward(), address(reward));
    }

    function testDeployAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockTargetLike someTarget = MockTargetLike(
            deployMockTarget(address(underlying), "Some Target", "ST", tDecimals)
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(someReward);

        // As we want to test guard calculation with a scale value different than 1e18 (which is the one used
        // on the mock contracts), we use the Mock2e18Factory which uses deploys Mock2e18Adapter adapters.
        // If we are testing with 4626, we can use the deployCropsFactory helper (we are not using
        // mocks on this case). NOTE: trying to use vm.mockCall to mock the scale call is not supported
        // as we would be mocking the adapter with a pre-computed address and does not work.
        MockCropFactory someFactory;
        if (is4626Target) {
            someFactory = MockCropFactory(deployCropsFactory(address(someTarget), rewardTokens, false));
        } else {
            BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
                stake: address(stake),
                oracle: ORACLE,
                ifee: ISSUANCE_FEE,
                stakeSize: STAKE_SIZE,
                minm: MIN_MATURITY,
                maxm: MAX_MATURITY,
                mode: MODE,
                tilt: 0,
                guard: DEFAULT_GUARD
            });
            someFactory = new Mock2e18Factory(
                address(divider),
                Constants.RESTRICTED_ADMIN,
                Constants.REWARDS_RECIPIENT,
                factoryParams,
                address(someReward)
            );
            someFactory.supportTarget(address(someTarget), true);
            divider.setIsTrusted(address(someFactory), true);
            periphery.setFactory(address(someFactory), true);
        }

        // deploy adapter via factory
        divider.setPeriphery(alice);
        MockCropAdapter adapter = MockCropAdapter(
            someFactory.deployAdapter(address(someTarget), abi.encode(address(someReward)))
        );
        assertTrue(address(adapter) != address(0));

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = adapter.adapterParams();
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(adapter.target(), address(someTarget));
        assertEq(adapter.name(), "Some Target Adapter");
        assertEq(adapter.symbol(), "ST-adapter");
        assertEq(adapter.ifee(), ISSUANCE_FEE);
        assertEq(oracle, ORACLE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(adapter.mode(), MODE);

        if (is4626Target) {
            assertEq(ERC4626CropAdapter(address(adapter)).reward(), address(someReward));
        } else {
            assertEq(adapter.reward(), address(someReward));
        }

        // assert scale is 2e18 (or 1e18 if 4626)
        uint256 scale = adapter.scale();
        assertEq(scale, is4626Target ? 1e18 : 2e18);

        // Guard has been calculated with underlying-ETH (18 decimals),
        // target-underlying (18 decimals) and ETH-USD (8 decimals)
        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        uint256 tDecimals = MockToken(adapter.target()).decimals();

        // On this test we assert that the guard calculated is close to the one calculated below
        // underlying-ETH price (18 decimals)
        uint256 underlyingPriceInEth = adapter.getUnderlyingPrice();

        // (1) Calculate Underlying-USD price (normalised to 18 decimals)
        uint256 price = underlyingPriceInEth.fmul(Constants.DEFAULT_CHAINLINK_ETH_PRICE, 1e8);

        // (2) Calculate Target-USD price (18 decimals)
        price = scale.fmul(price);

        // (3) Convert DEFAULT_GUARD (which is $100'000 in 18 decimals) to target
        // using target's price (18 decimals)
        uint256 guardInTarget = DEFAULT_GUARD.fdiv(price, 10**tDecimals);
        assertEq(guard, guardInTarget);

        // Sanity checks with constants values:
        // as underlying price is 1e18, ETH price is 1900 (in 8 decimals) and scale is 2e18,
        // (1) Underlying-USD price should be: 1e18 * (1900 * 1e8) -> normalised to 18 decimals = 1900 * 1e18
        // (2) Target-USD price should be: 2e18 * (1900 * 1e18) -> normalised to 18 decimals decimals = 3800 * 1e18
        // (3) and as the guard factory is $100'000 in 18 decimals
        // then guard should be: (100000 * 1e18) / (3800 * 1e18) -> normalised to target decimals =
        // * for 6 decimals target -> 26315789
        // * for 8 decimals target -> 2631578947
        // * for 18 decimals target -> 26315789473684210526
        // NOTE: if 4626 tests, sacle value is 1e18 so values would be:
        // * for 6 decimals target -> 52631578
        // * for 8 decimals target -> 5263157894
        // * for 18 decimals target -> 52631578947368421052
        if (tDecimals == 6) {
            assertEq(guard, is4626Target ? 52631578 : 26315789);
        } else if (tDecimals == 8) {
            assertEq(guard, is4626Target ? 5263157894 : 2631578947);
        } else if (tDecimals == 18) {
            assertEq(guard, is4626Target ? 52631578947368421052 : 26315789473684210526);
        }

        // check deployer can set trusted addresses
        someFactory.setAdapterTrusted(address(adapter), address(0xFEDE), true);
        assertTrue(adapter.isTrusted(address(0xFEDE)));
    }

    function testDeployAdapterDoesNotSetGuardWhenNotGuarded() public {
        // Set guarded mode in false
        divider.setGuarded(false);

        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(underlying), "Some Target", "ST", 18));
        MockFactory someFactory = MockFactory(deployFactory(address(someTarget)));
        divider.setPeriphery(alice);
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

        (, , uint256 guard, ) = divider.adapterMeta(address(adapter));
        assertEq(guard, 0);
    }

    function testDeployAdapterAndinitializeSeries() public {
        MockTargetLike someTarget;
        address someAdapter;

        {
            MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
            someTarget = MockTargetLike(deployMockTarget(address(someUnderlying), "Some Target", "ST", 18));

            address[] memory rewardTokens = new address[](1);
            rewardTokens[0] = address(new MockToken("Some Reward", "SR", 18));
            MockCropFactory someFactory = MockCropFactory(deployCropsFactory(address(someTarget), rewardTokens, false));

            someAdapter = periphery.deployAdapter(address(someFactory), address(someTarget), abi.encode(rewardTokens));
            assertTrue(someAdapter != address(0));
            uint256 scale = MockAdapter(someAdapter).scale();
            assertEq(scale, 1e18);
        }

        vm.warp(block.timestamp + 1 days);
        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 1, 0, 0, 0);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            someAdapter,
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));
    }

    function testCantDeployAdapterIfNotPeriphery() public {
        address[] memory rewardTokens;
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        factory.supportTarget(address(someTarget), true);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyPeriphery.selector));
        factory.deployAdapter(address(someTarget), abi.encode(rewardTokens));
    }

    function testFailDeployAdapterIfAlreadyExists() public {
        vm.prank(address(periphery));
        factory.deployAdapter(address(target), abi.encode(address(reward)));
    }

    function testSetRestrictedAdmin() public {
        assertEq(factory.restrictedAdmin(), Constants.RESTRICTED_ADMIN);

        // Can not set admin if not trusted
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x123));
        factory.setRestrictedAdmin(address(0x111));

        // Can set admin
        vm.expectEmit(true, true, true, true);
        emit RestrictedAdminChanged(Constants.RESTRICTED_ADMIN, address(0x111));

        factory.setRestrictedAdmin(address(0x111));
        assertEq(factory.restrictedAdmin(), address(0x111));
    }

    function testSetRewardsRecipient() public {
        assertEq(factory.rewardsRecipient(), Constants.REWARDS_RECIPIENT);

        // Can not set rewards recipient if not trusted
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x123));
        factory.setRewardsRecipient(address(0x111));

        // Can set rewards recipient
        vm.expectEmit(true, true, true, true);
        emit RewardsRecipientChanged(Constants.REWARDS_RECIPIENT, address(0x111));

        factory.setRewardsRecipient(address(0x111));
        assertEq(factory.rewardsRecipient(), address(0x111));
    }

    function testSetFactoryParams() public {
        BaseFactory.FactoryParams memory factoryParams;

        // Can not set factory params if not trusted
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x123));
        factory.setFactoryParams(factoryParams);

        // Can set rewards recipient
        factoryParams.stake = address(0xFED);
        factoryParams.oracle = address(0xFED);
        factoryParams.ifee = 111e18;
        factoryParams.stakeSize = 111e18;
        factoryParams.minm = 111e18;
        factoryParams.maxm = 111e18;
        factoryParams.mode = 1;
        factoryParams.tilt = 1;
        factoryParams.guard = 111e1;

        vm.expectEmit(true, true, true, true);
        emit FactoryParamsChanged(factoryParams);
        factory.setFactoryParams(factoryParams);

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
        ) = factory.factoryParams();

        assertEq(stake, factoryParams.stake);
        assertEq(oracle, factoryParams.oracle);
        assertEq(stakeSize, factoryParams.stakeSize);
        assertEq(minm, factoryParams.minm);
        assertEq(maxm, factoryParams.maxm);
        assertEq(ifee, factoryParams.ifee);
        assertEq(mode, factoryParams.mode);
        assertEq(tilt, factoryParams.tilt);
        assertEq(guard, factoryParams.guard);
    }

    /* ========== LOGS ========== */

    event RewardsRecipientChanged(address indexed recipient, address indexed newRecipient);
    event RestrictedAdminChanged(address indexed admin, address indexed newAdmin);
    event FactoryParamsChanged(BaseFactory.FactoryParams factoryParams);
}
