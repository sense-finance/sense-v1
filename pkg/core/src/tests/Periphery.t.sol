// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { TestHelper, MockTargetLike } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockAdapter, MockCropAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockFactory, MockCropFactory, Mock4626CropFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockSpacePool } from "./test-helpers/mocks/MockSpace.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { BalancerPool } from "../external/balancer/Pool.sol";
import { BalancerVault } from "../external/balancer/Vault.sol";
import { Constants } from "./test-helpers/Constants.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

contract PeripheryTest is TestHelper {
    using FixedMath for uint256;
    uint256 public DEADLINE = block.timestamp + 1000;

    function testDeployPeriphery() public {
        address spaceFactory = address(2);
        address balancerVault = address(3);
        Periphery somePeriphery = new Periphery(
            address(divider),
            spaceFactory,
            balancerVault,
            address(permit2),
            address(0)
        );
        assertTrue(address(somePeriphery) != address(0));
        assertEq(address(Periphery(somePeriphery).divider()), address(divider));
        assertEq(address(Periphery(somePeriphery).spaceFactory()), address(spaceFactory));
        assertEq(address(Periphery(somePeriphery).balancerVault()), address(balancerVault));
    }

    function testSponsorSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);

        vm.expectEmit(true, true, true, true);
        emit SeriesSponsored(address(adapter), maturity, bob);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and YTs onboarded on PoolManager (Fuse)
        // (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        // assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testNonPermitSponsorSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);

        // load bob's wallet with 1 stake
        deal(address(stake), bob, 1e18);

        // approve Periphery to pull Bob's stake
        vm.prank(bob);
        stake.approve(address(periphery), 1e18);

        vm.expectEmit(true, true, true, true);
        emit SeriesSponsored(address(adapter), maturity, bob);

        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));
    }

    function testSponsorSeriesWhenUnverifiedAdapter() public {
        divider.setPermissionless(true);
        MockCropAdapter adapter = new MockCropAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            DEFAULT_ADAPTER_PARAMS,
            address(reward)
        );

        divider.addAdapter(address(adapter));

        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and YTs NOT onboarded on PoolManager (Fuse)
        // (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        // assertTrue(status == PoolManager.SeriesStatus.NONE);
    }

    // Pool Manager tests (commented since we removed this feature from the Periphery)

    // function testSponsorSeriesWhenUnverifiedAdapterAndWithPoolFalse() public {
    //     divider.setPermissionless(true);

    //     BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
    //         oracle: ORACLE,
    //         stake: address(stake),
    //         stakeSize: STAKE_SIZE,
    //         minm: MIN_MATURITY,
    //         maxm: MAX_MATURITY,
    //         mode: 0,
    //         tilt: 0,
    //         level: DEFAULT_LEVEL
    //     });
    //     MockCropAdapter adapter = new MockCropAdapter(
    //         address(divider),
    //         address(target),
    //         !is4626Target ? target.underlying() : target.asset(),
    //         Constants.REWARDS_RECIPIENT,
    //         ISSUANCE_FEE,
    //         adapterParams,
    //         address(reward)
    //     );

    //     divider.addAdapter(address(adapter));

    //     uint256 maturity = getValidMaturity(2021, 10);
    //     Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
    //     vm.prank(bob);
    //     (address pt, address yt) = periphery.sponsorSeries(
    //         address(adapter),
    //         maturity,
    //         false,
    //         data,
    //         _getQuote(address(stake), address(stake))
    //     );

    //     // check pt and yt deployed
    //     assertTrue(pt != address(0));
    //     assertTrue(yt != address(0));

    //     // check Space pool is NOT deployed
    //     assertTrue(address(spaceFactory.pool()) == address(0));

    //     // check pt and YTs NOT onboarded on PoolManager (Fuse)
    //     (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
    //     assertTrue(status == PoolManager.SeriesStatus.NONE);
    // }

    // function testSponsorSeriesWhenPoolManagerZero() public {
    //     periphery.setPoolManager(address(0));
    //     periphery.verifyAdapter(address(adapter));

    //     // try sponsoring
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
    //     vm.prank(bob);
    //     (, address yt) = periphery.sponsorSeries(
    //         address(adapter),
    //         maturity,
    //         true,
    //         data,
    //         _getQuote(address(stake), address(stake))
    //     );
    //     assertTrue(yt != address(0));
    // }

    // function testFailSponsorSeriesWhenPoolManagerZero() public {
    //     periphery.setPoolManager(address(0));
    //     periphery.verifyAdapter(address(adapter));

    //     // try sponsoring
    //     uint256 maturity = getValidMaturity(2021, 10);
    //     vm.expectEmit(false, false, false, false);
    //     emit SeriesQueued(address(1), 2, address(3));
    //     Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
    //     vm.prank(bob);
    //     (, address yt) = periphery.sponsorSeries(
    //         address(adapter),
    //         maturity,
    //         true,
    //         data,
    //         _getQuote(address(stake), address(stake))
    //     );
    //     assertTrue(yt != address(0));
    // }

    function testDeployAdapter() public {
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));

        factory.supportTarget(address(newTarget), true);

        vm.expectEmit(false, false, false, false);
        emit AdapterDeployed(address(0));

        vm.expectEmit(false, false, false, false);
        emit AdapterVerified(address(0));

        vm.expectEmit(false, false, false, false);
        emit AdapterOnboarded(address(0));

        // onboard target
        address[] memory rewardTokens;
        periphery.deployAdapter(address(factory), address(newTarget), abi.encode(rewardTokens));
        // address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        // assertTrue(cTarget != address(0));
    }

    function testDeployCropAdapter() public {
        // deploy a Mock Crop Factory
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

        address cropFactory;
        if (is4626Target) {
            cropFactory = address(
                new Mock4626CropFactory(
                    address(divider),
                    Constants.RESTRICTED_ADMIN,
                    Constants.REWARDS_RECIPIENT,
                    factoryParams,
                    address(reward)
                )
            );
        } else {
            cropFactory = address(
                new MockCropFactory(
                    address(divider),
                    Constants.RESTRICTED_ADMIN,
                    Constants.REWARDS_RECIPIENT,
                    factoryParams,
                    address(reward)
                )
            );
        }
        divider.setIsTrusted(cropFactory, true);
        periphery.setFactory(cropFactory, true);

        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));
        MockFactory(cropFactory).supportTarget(address(newTarget), true);

        // onboard target
        address[] memory rewardTokens;
        periphery.deployAdapter(cropFactory, address(newTarget), abi.encode(rewardTokens));
        // address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        // assertTrue(cTarget != address(0));
    }

    function testDeployAdapterWhenPermissionless() public {
        divider.setPermissionless(true);
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));
        factory.supportTarget(address(newTarget), true);

        // onboard target
        address[] memory rewardTokens;
        periphery.deployAdapter(address(factory), address(newTarget), abi.encode(rewardTokens));
        // address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        // assertTrue(cTarget != address(0));
    }

    function testCantDeployAdapterIfTargetIsNotSupportedOnSpecificAdapter() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(someUnderlying), "Some Target", "ST", 18));
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        MockCropFactory someFactory = MockCropFactory(deployCropsFactory(address(someTarget), rewardTokens, false));

        // try deploying adapter using default factory
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        periphery.deployAdapter(address(factory), address(someTarget), abi.encode(rewardTokens));

        // try deploying adapter using new factory with supported target
        periphery.deployAdapter(address(someFactory), address(someTarget), abi.encode(rewardTokens));
    }

    function testCantDeployAdapterIfTargetIsNotSupported() public {
        address[] memory rewardTokens;
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(someUnderlying), "Some Target", "ST", 18));
        vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        periphery.deployAdapter(address(factory), address(newTarget), abi.encode(rewardTokens));
    }

    /* ========== admin update storage addresses ========== */

    // function testUpdatePoolManager() public {
    //     address oldPoolManager = address(periphery.poolManager());

    //     vm.record();
    //     address NEW_POOL_MANAGER = address(0xbabe);

    //     // Expect the new Pool Manager to be set, and for a "change" event to be emitted
    //     vm.expectEmit(true, false, false, true);
    //     emit PoolManagerChanged(oldPoolManager, NEW_POOL_MANAGER);

    //     // 1. Update the Pool Manager address
    //     periphery.setPoolManager(NEW_POOL_MANAGER);
    //     (, bytes32[] memory writes) = vm.accesses(address(periphery));

    //     // Check that the storage slot was updated correctly
    //     assertEq(address(periphery.poolManager()), NEW_POOL_MANAGER);
    //     // Check that only one storage slot was written to
    //     assertEq(writes.length, 1);
    // }

    function testUpdateSpaceFactory() public {
        address oldSpaceFactory = address(periphery.spaceFactory());

        vm.record();
        address NEW_SPACE_FACTORY = address(0xbabe);

        // Expect the new Space Factory to be set, and for a "change" event to be emitted
        vm.expectEmit(true, false, false, true);
        emit SpaceFactoryChanged(oldSpaceFactory, NEW_SPACE_FACTORY);

        // 1. Update the Space Factory address
        periphery.setSpaceFactory(NEW_SPACE_FACTORY);
        (, bytes32[] memory writes) = vm.accesses(address(periphery));

        // Check that the storage slot was updated correctly
        assertEq(address(periphery.spaceFactory()), NEW_SPACE_FACTORY);
        // Check that only one storage slot was written to
        assertEq(writes.length, 1);
    }

    // function testFuzzUpdatePoolManager(address lad) public {
    //     vm.record();
    //     vm.assume(lad != alice); // For any address other than the testing contract
    //     address NEW_POOL_MANAGER = address(0xbabe);

    //     // 1. Impersonate the fuzzed address and try to update the Pool Manager address
    //     vm.prank(lad);
    //     vm.expectRevert("UNTRUSTED");
    //     periphery.setPoolManager(NEW_POOL_MANAGER);

    //     (, bytes32[] memory writes) = vm.accesses(address(periphery));
    //     // Check that only no storage slots were written to
    //     assertEq(writes.length, 0);
    // }

    function testFuzzUpdateSpaceFactory(address lad) public {
        vm.record();
        vm.assume(lad != alice); // For any address other than the testing contract
        address NEW_SPACE_FACTORY = address(0xbabe);

        // 1. Impersonate the fuzzed address and try to update the Space Factory address
        vm.prank(lad);
        vm.expectRevert("UNTRUSTED");
        periphery.setSpaceFactory(NEW_SPACE_FACTORY);

        (, bytes32[] memory writes) = vm.accesses(address(periphery));
        // Check that only no storage slots were written to
        assertEq(writes.length, 0);
    }

    /* ========== admin onboarding tests ========== */

    function testAdminOnboardFactory() public {
        address NEW_FACTORY = address(0xbabe);

        // 1. onboard a new factory
        vm.expectEmit(true, false, false, true);
        emit FactoryChanged(NEW_FACTORY, true);
        assertTrue(!periphery.factories(NEW_FACTORY));
        periphery.setFactory(NEW_FACTORY, true);
        assertTrue(periphery.factories(NEW_FACTORY));

        // 2. remove new factory
        vm.expectEmit(true, false, false, true);
        emit FactoryChanged(NEW_FACTORY, false);
        periphery.setFactory(NEW_FACTORY, false);
        assertTrue(!periphery.factories(NEW_FACTORY));
    }

    function testAdminOnboardVerifiedAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter));
        periphery.onboardAdapter(address(otherAdapter), true);
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    function testAdminOnboardUnverifiedAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.onboardAdapter(address(otherAdapter), true);
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    function testAdminOnboardVerifiedAdapterWhenPermissionlesss() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter));
        periphery.onboardAdapter(address(otherAdapter), true);
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    function testAdminOnboardUnverifiedAdapterWhenPermissionlesss() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.onboardAdapter(address(otherAdapter), true);
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    /* ==========  non-admin onboarding tests ========== */

    function testOnboardVerifiedAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter)); // admin verification
        periphery.setIsTrusted(alice, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyPermissionless.selector));
        periphery.onboardAdapter(address(otherAdapter), true);
    }

    function testOnboardUnverifiedAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.setIsTrusted(alice, false); // admin verification

        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyPermissionless.selector));
        periphery.onboardAdapter(address(otherAdapter), true);
    }

    function testOnboardVerifiedAdapterWhenPermissionlesss() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter)); // admin verification
        periphery.setIsTrusted(alice, false);
        periphery.onboardAdapter(address(otherAdapter), true); // non admin onboarding
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    function testOnboardUnverifiedAdapterWhenPermissionlesss() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.setIsTrusted(alice, false);
        periphery.onboardAdapter(address(otherAdapter), true); // no-admin onboarding
        (, bool enabled, , ) = divider.adapterMeta(address(otherAdapter));
        assertTrue(enabled);
    }

    function testReOnboardVerifiedAdapterAfterUpgradingPeriphery() public {
        Periphery somePeriphery = new Periphery(
            address(divider),
            // address(poolManager),
            address(spaceFactory),
            address(balancerVault),
            address(permit2),
            address(0)
        );
        somePeriphery.onboardAdapter(address(adapter), false);

        assertTrue(periphery.verified(address(adapter)));

        (, bool enabled, , ) = divider.adapterMeta(address(adapter));
        assertTrue(enabled);

        // try sponsoring
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        assertTrue(yt != address(0));
    }

    /* ========== adapter verification tests ========== */

    function testAdminVerifyAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter)); // admin verification
        assertTrue(periphery.verified(address(otherAdapter)));
    }

    function testAdminVerifyAdapterWhenPermissionless() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter)); // admin verification
        assertTrue(periphery.verified(address(otherAdapter)));
    }

    // function testAdminVerifyAdapterWhenPoolManagerZero() public {
    //     MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
    //     MockTargetLike otherTarget = MockTargetLike(
    //         deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
    //     );
    //     MockAdapter otherAdapter = MockAdapter(
    //         deployMockAdapter(address(divider), address(otherTarget), address(reward))
    //     );
    //     periphery.setPoolManager(address(0));

    //     periphery.verifyAdapter(address(otherAdapter));

    //     assertTrue(periphery.verified(address(otherAdapter)));
    // }

    // function testFailAdminVerifyAdapterWhenPoolManagerZero() public {
    //     MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
    //     MockTargetLike otherTarget = MockTargetLike(
    //         deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
    //     );
    //     MockAdapter otherAdapter = MockAdapter(
    //         deployMockAdapter(address(divider), address(otherTarget), address(reward))
    //     );
    //     periphery.setPoolManager(address(0));

    //     vm.expectEmit(false, false, false, false);
    //     emit TargetAdded(address(1), address(2));
    //     periphery.verifyAdapter(address(otherAdapter));

    //     assertTrue(periphery.verified(address(otherAdapter)));
    // }

    function testCantVerifyAdapterNonAdmin() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.setIsTrusted(alice, false);
        vm.expectRevert("UNTRUSTED");
        periphery.verifyAdapter(address(otherAdapter)); // non-admin verification
        assertTrue(!periphery.verified(address(otherAdapter)));
    }

    function testCantVerifyAdapterNonAdminWhenPermissionless() public {
        divider.setPermissionless(true);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.setIsTrusted(alice, false);
        vm.expectRevert("UNTRUSTED");
        periphery.verifyAdapter(address(otherAdapter)); // non-admin verification
        assertTrue(!periphery.verified(address(otherAdapter)));
    }

    /* ========== swap tests ========== */

    function testSwapTargetForPTsWhenDeadlineExpired() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.swapForPTs(
                address(adapter),
                maturity,
                tBal,
                DEADLINE,
                0,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }
    }

    function testFuzzSwapTargetForPTs(address receiver) public {
        vm.assume(receiver != 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c);
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 ytBalBefore = ERC20(divider.yt(address(adapter), maturity)).balanceOf(receiver);
        uint256 ptBalBefore = ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver);

        // unwrap target into underlying & calculate underlying swapped to pt
        uint256 ptBal = tBal.fmul(adapter.scale()).fdiv(balancerVault.EXCHANGE_RATE());

        vm.expectEmit(true, false, false, false);
        emit Swapped(bob, "0", adapter.target(), address(0), 0, 0, msg.sig);

        {
            data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.swapForPTs(
                address(adapter),
                maturity,
                tBal,
                DEADLINE,
                0,
                receiver,
                data,
                _getQuote(address(target), address(0))
            );
        }

        assertEq(ytBalBefore, ERC20(divider.yt(address(adapter), maturity)).balanceOf(receiver));
        assertEq(ptBalBefore + ptBal, ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver));
    }

    function testFuzzSwapUnderlyingForPTs(address receiver) public {
        vm.assume(receiver != 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c);
        uint256 uBal = 100 * (10**uDecimals);
        uint256 maturity = getValidMaturity(2021, 10);
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }
        uint256 scale = adapter.scale();

        // wrap underlying into target
        uint256 tBal;
        if (!is4626Target) {
            tBal = uDecimals > tDecimals ? uBal.fdivUp(scale) / SCALING_FACTOR : uBal.fdivUp(scale) * SCALING_FACTOR;
        } else {
            tBal = target.previewDeposit(uBal);
        }

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 100000 * 10**tDecimals);

        uint256 ytBalBefore = ERC20(divider.yt(address(adapter), maturity)).balanceOf(receiver);
        uint256 ptBalBefore = ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver);

        // calculate underlying swapped to pt
        uint256 ptBal = tBal.fdiv(balancerVault.EXCHANGE_RATE());

        initUser(bob, target, uBal);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(underlying));

        vm.expectEmit(true, false, false, false);
        emit Swapped(bob, "0", adapter.target(), address(0), 0, 0, msg.sig);

        vm.prank(bob);
        periphery.swapForPTs(
            address(adapter),
            maturity,
            uBal,
            DEADLINE,
            0,
            receiver,
            data,
            _getQuote(address(underlying), address(0))
        );

        assertEq(ytBalBefore, ERC20(divider.yt(address(adapter), maturity)).balanceOf(receiver));
        assertApproxEqAbs(ptBalBefore + ptBal, ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver), 1);
    }

    function testFuzzSwapPTsForTarget(address receiver) public {
        vm.assume(receiver != address(balancerVault));
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, ) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(receiver);
        uint256 ptBalBefore = ERC20(pt).balanceOf(bob);

        // calculate pt swapped to target
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 swapped = ptBalBefore.fmul(rate);

        vm.prank(bob);
        ERC20(pt).approve(address(permit2), ptBalBefore);

        vm.expectEmit(true, false, false, false);
        emit Swapped(bob, "0", adapter.target(), address(0), 0, 0, msg.sig);

        data = generatePermit(bobPrivKey, address(periphery), pt);
        vm.prank(bob);
        periphery.swapPTs(
            address(adapter),
            maturity,
            ptBalBefore,
            DEADLINE,
            0,
            receiver,
            data,
            _getQuote(address(0), address(target))
        );

        assertEq(tBalBefore + swapped, target.balanceOf(receiver));
    }

    function testSwapFuzzPTsForTargetAutoRedeem(address receiver) public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        // settle series
        vm.warp(maturity);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(receiver);
        uint256 ptBalBefore = ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver);

        vm.prank(bob);
        ERC20(divider.pt(address(adapter), maturity)).approve(address(permit2), ptBalBefore);

        (, , , , , , , uint256 mscale, ) = divider.series(address(adapter), maturity);
        uint256 tBalRedeemed = ptBalBefore.fdiv(mscale);
        vm.expectEmit(true, true, true, false);
        emit PTRedeemed(address(adapter), maturity, tBalRedeemed);

        data = generatePermit(bobPrivKey, address(periphery), divider.pt(address(adapter), maturity));
        vm.prank(bob);
        uint256 redeemed = periphery.swapPTs(
            address(adapter),
            maturity,
            ptBalBefore,
            DEADLINE,
            0,
            receiver,
            data,
            _getQuote(address(0), address(target))
        );
        assertEq(ERC20(divider.pt(address(adapter), maturity)).balanceOf(receiver), 0);
        assertEq(tBalBefore + redeemed, target.balanceOf(receiver));
    }

    function testSwapFuzzPTsForTargetNoAutoRedeemIfRedeemRestricted() public {
        uint256 maturity = getValidMaturity(2021, 10);

        // create adapter with ptRedeem restricted
        target = MockTargetLike(deployMockTarget(address(underlying), "Compound USDC", "cUSDC", tDecimals));

        divider.setPermissionless(true);
        DEFAULT_ADAPTER_PARAMS.level = 0x1 + 0x2 + 0x4 + 0x8; // redeem restricted;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        periphery.verifyAdapter(address(adapter));
        periphery.onboardAdapter(address(adapter), true);
        divider.setGuard(address(adapter), 10 * 2**128);

        // sponsor series
        stake.approve(address(periphery), type(uint256).max);
        Periphery.PermitData memory data;
        (address pt, ) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(0))
        );

        spaceFactory.create(address(adapter), maturity);
        adapter.scale();
        addLiquidityToBalancerVault(address(adapter), maturity, 1000 * 10**tDecimals);

        // settle series
        vm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);

        uint256 ptBalBefore = ERC20(pt).balanceOf(jim);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);

        vm.startPrank(bob);
        deal(divider.pt(address(adapter), maturity), bob, 1e18); // load bob's wallet with 1 PT
        ERC20(pt).approve(address(permit2), 1e18); // approve permit2 to pull PT
        data = generatePermit(bobPrivKey, address(periphery), pt);
        uint256 tBal = periphery.swapPTs(
            address(adapter),
            maturity,
            1e18,
            DEADLINE,
            0,
            jim,
            data,
            _getQuote(address(0), address(target))
        );
        vm.stopPrank();

        assertEq(tBal, ERC20(adapter.target()).balanceOf(jim) - tBalBefore);
        assertEq(ptBalBefore, ERC20(pt).balanceOf(jim));
        assertEq(ERC20(pt).balanceOf(bob), 0);
    }

    function testFuzzSwapPTsForUnderlying(address receiver) public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, ) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(receiver);
        uint256 ptBalBefore = ERC20(pt).balanceOf(bob);

        uint256 uBal;
        {
            // calculate pt swapped to target
            uint256 rate = balancerVault.EXCHANGE_RATE();
            uint256 swapped = ptBalBefore.fmul(rate);

            // unwrap target into underlying
            uint256 scale = adapter.scale();
            uBal = uDecimals > tDecimals ? swapped.fmul(scale) * SCALING_FACTOR : swapped.fmul(scale) / SCALING_FACTOR;
        }

        vm.prank(bob);
        ERC20(pt).approve(address(permit2), ptBalBefore);

        vm.expectEmit(true, false, false, false);
        emit Swapped(bob, "0", adapter.target(), address(0), 0, 0, msg.sig);

        data = generatePermit(bobPrivKey, address(periphery), pt);
        vm.prank(bob);
        periphery.swapPTs(
            address(adapter),
            maturity,
            ptBalBefore,
            DEADLINE,
            0,
            receiver,
            data,
            _getQuote(address(0), address(underlying))
        );

        assertEq(uBalBefore + uBal, ERC20(underlying).balanceOf(receiver));
    }

    function testFuzzSwapYTsForTarget(address receiver) public {
        vm.assume(receiver != 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c);
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );
        uint256 lscale = adapter.scale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000 * 10**tDecimals);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        uint256 ytBalBefore = ERC20(yt).balanceOf(bob);
        uint256 tBalBefore = target.balanceOf(receiver);

        uint256 remainingYTInTarget;
        {
            uint256 targetToBorrow = 9025 * 10**(tDecimals - 2);
            // swap underlying for PT on Yieldspace pool
            uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE());

            // combine pt and yt
            uint256 tCombined = zSwapped.fdiv(lscale);
            remainingYTInTarget = tCombined - targetToBorrow;
        }

        vm.prank(bob);
        ERC20(yt).approve(address(permit2), ytBalBefore);
        data = generatePermit(bobPrivKey, address(periphery), yt);
        vm.prank(bob);
        periphery.swapYTs(
            address(adapter),
            maturity,
            ytBalBefore,
            DEADLINE,
            remainingYTInTarget,
            receiver,
            data,
            _getQuote(address(0), address(target))
        );

        assertEq(tBalBefore + remainingYTInTarget, target.balanceOf(receiver));
    }

    /* ========== liquidity tests ========== */

    function testAddLiquidityFirstTimeWithSellYieldModeShouldNotIssue() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
            address(adapter),
            maturity,
            tBal,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            0,
            alice,
            data,
            _getQuote(address(target), address(0))
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityFirstTimeWithHoldYieldModeShouldNotIssue() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
            address(adapter),
            maturity,
            tBal,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            1,
            alice,
            data,
            _getQuote(address(target), address(0))
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        // init liquidity
        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        periphery.addLiquidity(
            address(adapter),
            maturity,
            1,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            0,
            bob,
            data,
            _getQuote(address(target), address(0))
        );

        uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
            address(adapter),
            maturity,
            tBal,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            0,
            alice,
            data,
            _getQuote(address(target), address(0))
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        // init liquidity
        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        periphery.addLiquidity(
            address(adapter),
            maturity,
            1,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            0,
            bob,
            data,
            _getQuote(address(target), address(0))
        );

        uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
            address(adapter),
            maturity,
            tBal,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            1,
            alice,
            data,
            _getQuote(address(target), address(0))
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(alice);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYT() public {
        uint256 tBal = 100 * 10**tDecimals;

        uint256 maturity = getValidMaturity(2021, 10);
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }
        uint256 lscale = adapter.scale();

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                1,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                0,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        // calculate targetToBorrow
        uint256 targetToBorrow;
        {
            address pt = divider.pt(address(adapter), maturity);
            // compute target
            uint256 tBase = 10**tDecimals;
            uint256 ptiBal = ERC20(pt).balanceOf(address(balancerVault));
            uint256 targetiBal = target.balanceOf(address(balancerVault));
            uint256 computedTarget = tBal.fmul(
                ptiBal.fdiv(adapter.scale().fmul(targetiBal).fmul(FixedMath.WAD - adapter.ifee()) + ptiBal, tBase),
                tBase
            ); // ABDK formula

            // to issue
            uint256 fee = computedTarget.fmul(adapter.ifee());
            uint256 toBeIssued = (computedTarget - fee).fmul(lscale);

            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            targetToBorrow = pool.onSwap(
                BalancerPool.SwapRequest({
                    kind: BalancerVault.SwapKind.GIVEN_OUT,
                    tokenIn: ERC20(address(target)),
                    tokenOut: ERC20(pt),
                    amount: toBeIssued,
                    poolId: 0,
                    lastChangeBlock: 0,
                    from: address(0),
                    to: address(0),
                    userData: ""
                }),
                0,
                0
            );
        }

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);
        uint256 jimTBalBefore = ERC20(adapter.target()).balanceOf(jim);
        {
            uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim);
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                0,
                jim,
                data,
                _getQuote(address(target), address(0))
            );
            assertTrue(targetBal > 0);
            assertTrue(ytBal > 0);
            uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim);
            assertEq(lpShares, lpBalAfter - lpBalBefore);
            assertEq(lpBalBefore + 100e18, lpBalAfter);
        }

        assertEq(tBalBefore - tBal, ERC20(adapter.target()).balanceOf(bob));

        // calculate target to borrow
        {
            // swap Target for PT on Yieldspace pool
            uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE());
            // combine pt and yt
            uint256 tCombined = zSwapped.fdiv(lscale);
            uint256 remainingYTInTarget = tCombined - targetToBorrow;
            assertEq(jimTBalBefore + remainingYTInTarget, ERC20(adapter.target()).balanceOf(jim));
        }
    }

    function testAddLiquidityAndHoldYT() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000 * 10**tDecimals);

        // init liquidity
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            target.balanceOf(bob);
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                1,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            // calculate YTs to be issued
            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
            uint256 scale = adapter.scale();
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(
                    scale.fmul(balances[0]).fmul(FixedMath.WAD - adapter.ifee()) + balances[1],
                    10**tDecimals
                ),
                10**tDecimals
            ); // ABDK formula

            uint256 fee = proportionalTarget.fmul(adapter.ifee());
            toBeIssued = (proportionalTarget - fee).fmul(scale);
        }

        {
            address yt = divider.yt(address(adapter), maturity);
            uint256 ytBalBefore = ERC20(yt).balanceOf(jim);
            uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim);
            uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                jim,
                data,
                _getQuote(address(target), address(0))
            );

            assertEq(targetBal, 0);
            assertTrue(ytBal > 0);
            assertEq(lpShares, ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim) - lpBalBefore);

            // bob gets his target balance decreased
            assertEq(tBalBefore - tBal, ERC20(adapter.target()).balanceOf(bob));

            // jim gets his shares and YT balances increased
            assertEq(lpBalBefore + 100e18, ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim));
            assertEq(ytBalBefore + toBeIssued, ERC20(yt).balanceOf(jim));
        }
    }

    function testAddLiquidityFromUnderlyingAndHoldYT() public {
        uint256 uBal = 100 * 10**uDecimals; // we assume target = underlying as scale is 1e18
        uint256 maturity = getValidMaturity(2021, 10);
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000 * 10**tDecimals);

        // init liquidity
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                1,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim);
        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(bob);
        uint256 ytBalBefore = ERC20(divider.yt(address(adapter), maturity)).balanceOf(jim);

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            uint256 lscale = adapter.scale();
            // calculate YTs to be issued
            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());

            // wrap underlying into target
            uint256 tBal;
            if (!is4626Target) {
                tBal = uDecimals > tDecimals
                    ? uBal.fdivUp(lscale) / SCALING_FACTOR
                    : uBal.fdivUp(lscale) * SCALING_FACTOR;
            } else {
                tBal = target.previewDeposit(uBal);
            }

            // calculate proportional target to add to pool
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(FixedMath.WAD - adapter.ifee()).fmul(balances[0]) + balances[1])
            ); // ABDK formula

            // calculate amount of target to issue
            uint256 fee = uint256(adapter.ifee()).fmul(proportionalTarget);
            toBeIssued = (proportionalTarget - fee).fmul(lscale);
        }

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(underlying));
            vm.prank(bob);
            (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidity(
                address(adapter),
                maturity,
                uBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                jim,
                data,
                _getQuote(address(underlying), address(0))
            );

            assertEq(targetBal, 0);
            assertTrue(ytBal > 0);
            assertEq(lpShares, ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim) - lpBalBefore);

            assertEq(uBalBefore - uBal, ERC20(adapter.underlying()).balanceOf(bob));
            assertEq(lpBalBefore + 100e18, ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(jim));
            assertEq(toBeIssued, ytBal);
            assertEq(ytBalBefore + toBeIssued, ERC20(divider.yt(address(adapter), maturity)).balanceOf(jim));
        }
    }

    function testRemoveLiquidityBeforeMaturity() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
            uint256 proportionalTarget = tBal *
                (balances[1] / ((1e18 * balances[0] * (FixedMath.WAD - adapter.ifee())) / FixedMath.WAD + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), tDecimals).fmul(proportionalTarget, 10**tDecimals);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        data = generatePermit(bobPrivKey, address(periphery), address(target));
        vm.startPrank(bob);
        periphery.addLiquidity(
            address(adapter),
            maturity,
            tBal,
            Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
            1,
            bob,
            data,
            _getQuote(address(target), address(0))
        );
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);

        // calculate liquidity added
        {
            // minAmountsOut to target
            uint256 uBal = minAmountsOut[1].fmul(balancerVault.EXCHANGE_RATE()); // pt to underlying
            tBal = (minAmountsOut[0] + uBal).fdiv(lscale); // (pt (in underlying) + underlying) to target
        }

        uint256 lpBal = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);
        MockSpacePool(spaceFactory.pools(address(adapter), maturity)).approve(address(permit2), lpBal);
        data = generatePermit(bobPrivKey, address(periphery), address(spaceFactory.pools(address(adapter), maturity)));
        (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
            address(adapter),
            maturity,
            lpBal,
            Periphery.RemoveLiquidityParams(0, minAmountsOut, DEADLINE),
            true,
            alice,
            data,
            _getQuote(address(0), address(target))
        );
        vm.stopPrank();

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(alice);
        uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);

        assertEq(targetBal, tBalAfter - tBalBefore);
        assertEq(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
        assertEq(ptBal, 0);
    }

    function testRemoveLiquidityOnMaturity() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }

        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
            uint256 proportionalTarget = tBal * (balances[1] / (1e18 * balances[0] + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), tDecimals).fmul(proportionalTarget, 10**tDecimals);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        // settle series
        vm.warp(maturity);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
        lscale = adapter.scale();

        {
            address pt = divider.pt(address(adapter), maturity);
            uint256 ptBalBefore = ERC20(pt).balanceOf(jim);
            uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);
            uint256 lpBal = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);

            vm.startPrank(bob);
            MockSpacePool(spaceFactory.pools(address(adapter), maturity)).approve(address(permit2), lpBal);
            Periphery.PermitData memory data = generatePermit(
                bobPrivKey,
                address(periphery),
                spaceFactory.pools(address(adapter), maturity)
            );
            (uint256 targetBal, ) = periphery.removeLiquidity(
                address(adapter),
                maturity,
                lpBal,
                Periphery.RemoveLiquidityParams(0, minAmountsOut, DEADLINE),
                true,
                jim,
                data,
                _getQuote(address(0), address(target))
            );
            vm.stopPrank();

            uint256 tBalAfter = ERC20(adapter.target()).balanceOf(jim);
            assertEq(ptBalBefore, ERC20(pt).balanceOf(jim));
            assertEq(targetBal, tBalAfter - tBalBefore);
            assertApproxEqAbs(tBalBefore + tBal, tBalAfter);
            assertEq(ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob), 0);
        }
    }

    function testRemoveLiquidityOnMaturityAndPTRedeemRestricted() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        // // create adapter with ptRedeem restricted
        // MockToken underlying = new MockToken("Usdc Token", "USDC", uDecimals);
        target = MockTargetLike(deployMockTarget(address(underlying), "Compound USDC", "cUSDC", tDecimals));

        divider.setPermissionless(true);
        DEFAULT_ADAPTER_PARAMS.level = 0x1 + 0x2 + 0x4 + 0x8; // redeem restricted;
        adapter = MockCropAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        periphery.verifyAdapter(address(adapter));
        periphery.onboardAdapter(address(adapter), true);
        divider.setGuard(address(adapter), 10 * 2**128);

        // approvals for depositing
        underlying.approve(address(target), type(uint256).max);
        vm.prank(bob);
        underlying.approve(address(target), type(uint256).max);

        // get some target for Alice and Bob
        if (!is4626Target) {
            target.mint(alice, 10000000 * 10**tDecimals);
            vm.prank(bob);
            target.mint(bob, 10000000 * 10**tDecimals);
        } else {
            underlying.mint(alice, 10000000 * 10**uDecimals);
            underlying.mint(bob, 10000000 * 10**uDecimals);
            target.deposit(10000000 * 10**uDecimals, alice);
            vm.prank(bob);
            target.deposit(10000000 * 10**uDecimals, bob);
        }

        {
            vm.prank(bob);
            target.approve(address(permit2), type(uint256).max);
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(0)));
        }

        spaceFactory.create(address(adapter), maturity);
        adapter.scale();
        addLiquidityToBalancerVault(address(adapter), maturity, 1000 * 10**tDecimals);

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        // settle series
        vm.warp(maturity);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
        {
            address pt = divider.pt(address(adapter), maturity);
            uint256 ptBalBefore = ERC20(pt).balanceOf(jim);
            uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);
            uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);

            uint256[] memory minAmountsOut = new uint256[](2);
            minAmountsOut[0] = 2 * 10**tDecimals;
            minAmountsOut[1] = 1 * 10**tDecimals;

            vm.startPrank(bob);
            MockSpacePool(spaceFactory.pools(address(adapter), maturity)).approve(address(permit2), 3e18);
            Periphery.PermitData memory data = generatePermit(
                bobPrivKey,
                address(periphery),
                address(spaceFactory.pools(address(adapter), maturity))
            );
            (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
                address(adapter),
                maturity,
                3 * 10**tDecimals,
                Periphery.RemoveLiquidityParams(0, minAmountsOut, DEADLINE),
                true,
                jim,
                data,
                _getQuote(address(0), address(target))
            );
            vm.stopPrank();

            uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);
            assertEq(lpBalBefore, lpBalAfter + 3 * 10**tDecimals);
            assertEq(targetBal, ERC20(adapter.target()).balanceOf(jim) - tBalBefore);
            assertEq(ptBalBefore, ERC20(pt).balanceOf(jim) - minAmountsOut[1]);
            assertEq(ptBal, ERC20(pt).balanceOf(jim) - ptBalBefore);
            assertEq(ptBal, 10**tDecimals);
        }
    }

    function testRemoveLiquidityWhenOneSideLiquidity() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }

        // add one side liquidity
        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        {
            address pt = divider.pt(address(adapter), maturity);
            uint256 ptBalBefore = ERC20(pt).balanceOf(jim);
            uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);
            uint256 lpBalBefore = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);

            vm.startPrank(bob);
            MockSpacePool(spaceFactory.pools(address(adapter), maturity)).approve(address(permit2), lpBalBefore);
            Periphery.PermitData memory data = generatePermit(
                bobPrivKey,
                address(periphery),
                spaceFactory.pools(address(adapter), maturity)
            );
            uint256[] memory minAmountsOut = new uint256[](2);
            (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
                address(adapter),
                maturity,
                lpBalBefore,
                Periphery.RemoveLiquidityParams(0, minAmountsOut, DEADLINE),
                true,
                jim,
                data,
                _getQuote(address(0), address(target))
            );
            vm.stopPrank();

            uint256 tBalAfter = ERC20(adapter.target()).balanceOf(jim);
            uint256 lpBalAfter = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);
            uint256 ptBalAfter = ERC20(pt).balanceOf(jim);

            assertTrue(tBalAfter > 0);
            assertEq(targetBal, tBalAfter - tBalBefore);
            assertEq(ptBalAfter, ptBalBefore);
            assertEq(lpBalAfter, 0);
            assertEq(ptBal, 0);
            assertTrue(lpBalBefore > 0);
        }
    }

    // TODO: stack to deep (fix!)
    // function testRemoveLiquidityAndSkipSwap() public {
    //     uint256 tBal = 100 * 10**tDecimals;
    //     uint256 maturity = getValidMaturity(2021, 10);

    //     {
    //         Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
    //         vm.prank(bob);
    //         periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
    //     }

    //     uint256[] memory minAmountsOut = new uint256[](2);

    //     // add liquidity to mockUniSwapRouter
    //     addLiquidityToBalancerVault(maturity, 1000 * 10**tDecimals);

    //     uint256 ptToBeIssued;
    //     {
    //         uint256 lscale = adapter.scale();
    //         // calculate pt to be issued when adding liquidity
    //         MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
    //         (, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
    //         uint256 fee = adapter.ifee();
    //         uint256 tBase = 10**tDecimals;
    //         uint256 proportionalTarget = tBal.fmul(
    //             balances[1].fdiv(lscale.fmul(FixedMath.WAD - fee).fmul(balances[0]) + balances[1], tBase),
    //             tBase
    //         );
    //         ptToBeIssued = proportionalTarget.fmul(lscale);

    //         // prepare minAmountsOut for removing liquidity
    //         minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
    //         minAmountsOut[1] = ptToBeIssued; // pt to be issued
    //     }

    //     {
    //         Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
    //         vm.prank(bob);
    //         periphery.addLiquidity(
    //             address(adapter),
    //             maturity,
    //             tBal,
    //             0,
    //             type(uint256).max,
    //             1,
    //             address(this),
    //             data,
    //             _getQuote(address(target), address(0))
    //         );
    //     }

    //     {
    //         // address pt = divider.pt(address(adapter), maturity);
    //         uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);
    //         uint256 ptBalBefore = ERC20(divider.pt(address(adapter), maturity)).balanceOf(jim);
    //         uint256 lpBal = ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob);

    //         MockSpacePool(spaceFactory.pools(address(adapter), maturity)).approve(address(permit2), lpBal);
    //         Periphery.PermitData memory data = generatePermit(
    //             bobPrivKey,
    //             address(periphery),
    //             spaceFactory.pools(address(adapter), maturity)
    //         );
    //         vm.prank(bob);
    //         (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
    //             address(adapter),
    //             maturity,
    //             lpBal,
    //             minAmountsOut,
    //             0,
    //             false,
    //             jim,
    //             data,
    //             _getQuote(address(0), divider.pt(address(adapter), maturity)) // do not sell PTs to target
    //         );

    //         // uint256 tBalAfter = ERC20(adapter.target()).balanceOf(jim);
    //         assertEq(ERC20(adapter.target()).balanceOf(jim), tBalBefore + targetBal);
    //         assertEq(ERC20(spaceFactory.pools(address(adapter), maturity)).balanceOf(bob), 0);
    //         assertEq(ptBal, ptToBeIssued);
    //         assertEq(ERC20(divider.pt(address(adapter), maturity)).balanceOf(jim), ptBalBefore + ptToBeIssued);
    //     }
    // }

    function testRemoveLiquidityToUnderlying() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
            vm.prank(bob);
            periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));
        }
        address pool = spaceFactory.pools(address(adapter), maturity);
        vm.warp(block.timestamp + 5 days);
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 ptToBeIssued;
        uint256 targetToBeAdded;
        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(MockSpacePool(pool).getPoolId());
            uint256 fee = adapter.ifee();
            uint256 tBase = 10**tDecimals;
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(FixedMath.WAD - fee).fmul(balances[0]) + balances[1], tBase),
                tBase
            );
            ptToBeIssued = proportionalTarget.fmul(lscale);
            targetToBeAdded = (tBal - proportionalTarget); // target amount
            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = targetToBeAdded;
            minAmountsOut[1] = ptToBeIssued; // pt to be issued
        }

        {
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(target));
            vm.prank(bob);
            periphery.addLiquidity(
                address(adapter),
                maturity,
                tBal,
                Periphery.AddLiquidityParams(0, type(uint256).max, DEADLINE),
                1,
                bob,
                data,
                _getQuote(address(target), address(0))
            );
        }

        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(jim);
        {
            vm.startPrank(bob);
            MockSpacePool(pool).approve(address(permit2), type(uint256).max);
            Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), pool);
            (uint256 underlyingBal, uint256 ptBal) = periphery.removeLiquidity(
                address(adapter),
                maturity,
                ERC20(pool).balanceOf(bob),
                Periphery.RemoveLiquidityParams(0, minAmountsOut, DEADLINE),
                false,
                jim,
                data,
                _getQuote(address(0), adapter.underlying())
            );
            vm.stopPrank();
            assertEq(ERC20(pool).balanceOf(bob), 0);
            assertEq(ptBal, ptToBeIssued);
            assertEq(uBalBefore + underlyingBal, ERC20(adapter.underlying()).balanceOf(jim));
            assertEq(
                underlyingBal,
                uDecimals > tDecimals
                    ? targetToBeAdded.fmul(lscale) * SCALING_FACTOR
                    : targetToBeAdded.fmul(lscale) / SCALING_FACTOR
            );
        }
    }

    /* ========== issuance tests ========== */
    function testCanReceiveETH() public {
        // we make sure functions have the payable modifier, otherwise, this would not even compile
        Periphery.PermitData memory permit;
        Periphery.PermitBatchData memory batchPermit;
        uint256[] memory minAmountsOut;

        vm.expectRevert();
        periphery.sponsorSeries{ value: 1e18 }(address(0), 0, false, permit, _getQuote(address(0), address(0)));

        vm.expectRevert();
        periphery.swapForPTs{ value: 1e18 }(
            address(0),
            0,
            0,
            0,
            0,
            address(0),
            permit,
            _getQuote(address(0), address(0))
        );

        vm.expectRevert();
        periphery.swapForYTs{ value: 1e18 }(
            address(0),
            0,
            0,
            0,
            0,
            0,
            address(0),
            permit,
            _getQuote(address(0), address(0))
        );

        vm.expectRevert();
        periphery.swapPTs{ value: 1e18 }(address(0), 0, 0, 0, 0, address(0), permit, _getQuote(address(0), address(0)));

        vm.expectRevert();
        periphery.swapYTs{ value: 1e18 }(address(0), 0, 0, 0, 0, address(0), permit, _getQuote(address(0), address(0)));

        vm.expectRevert();
        periphery.addLiquidity{ value: 1e18 }(
            address(0),
            0,
            0,
            Periphery.AddLiquidityParams(0, 0, 0),
            0,
            address(0),
            permit,
            _getQuote(address(0), address(0))
        );

        vm.expectRevert();
        periphery.removeLiquidity{ value: 1e18 }(
            address(0),
            0,
            0,
            Periphery.RemoveLiquidityParams(0, minAmountsOut, 0),
            false,
            address(0),
            permit,
            _getQuote(address(0), address(0))
        );

        vm.expectRevert();
        periphery.issue{ value: 1e18 }(address(0), 0, 0, jim, permit, _getQuote(address(0), address(0)));

        vm.expectRevert();
        periphery.combine{ value: 1e18 }(address(0), 0, 0, address(0), batchPermit, _getQuote(address(0), address(0)));
    }

    function testIssue() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        uint256 tBalSubFee = tBal - tBal.fmul(adapter.ifee());
        uint256 uBal = tBalSubFee.fmul(adapter.scale());

        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);
        uint256 ytBalBefore = ERC20(yt).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);

        data = generatePermit(jimPrivKey, address(periphery), address(target));
        vm.prank(jim);
        periphery.issue(address(adapter), maturity, tBal, jim, data, _getQuote(address(target), address(0)));

        assertEq(ptBalBefore + uBal, ERC20(pt).balanceOf(jim));
        assertEq(ytBalBefore + uBal, ERC20(yt).balanceOf(jim));
        assertEq(tBalBefore, ERC20(adapter.target()).balanceOf(jim) + tBal);
    }

    function testIssueFromUnderlying() public {
        uint256 uBal = 100 * 10**uDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        uint256 uBalSubFee = uBal - uBal.fmul(adapter.ifee());
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);
        uint256 ytBalBefore = ERC20(yt).balanceOf(alice);
        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(alice);

        data = generatePermit(jimPrivKey, address(periphery), address(underlying));
        vm.prank(jim);
        periphery.issue(address(adapter), maturity, uBal, jim, data, _getQuote(address(underlying), address(0)));

        assertEq(ptBalBefore + uBalSubFee, ERC20(pt).balanceOf(jim));
        assertEq(ytBalBefore + uBalSubFee, ERC20(yt).balanceOf(jim));
        assertEq(uBalBefore, ERC20(adapter.underlying()).balanceOf(jim) + uBal);
    }

    function testCombine() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        vm.startPrank(jim);
        data = generatePermit(jimPrivKey, address(periphery), address(target));
        uint256 uBal = periphery.issue(
            address(adapter),
            maturity,
            tBal,
            jim,
            data,
            _getQuote(address(target), address(0))
        );

        uint256 ptBalBefore = ERC20(pt).balanceOf(jim);
        uint256 ytBalBefore = ERC20(yt).balanceOf(jim);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(jim);

        ERC20(pt).approve(address(permit2), ptBalBefore);
        ERC20(yt).approve(address(permit2), ytBalBefore);
        address[] memory tokens = new address[](2);
        tokens[0] = pt;
        tokens[1] = yt;
        Periphery.SwapQuote memory quote = _getQuote(address(0), address(target));
        Periphery.PermitBatchData memory bdata = generatePermit(jimPrivKey, address(periphery), tokens);
        periphery.combine(address(adapter), maturity, uBal, jim, bdata, quote);

        assertEq(ptBalBefore - uBal, ERC20(pt).balanceOf(jim));
        assertEq(ytBalBefore - uBal, ERC20(yt).balanceOf(jim));

        uint256 tBalSubFee = tBal - tBal.fmul(adapter.ifee());
        assertEq(tBalBefore, ERC20(adapter.target()).balanceOf(jim) - tBalSubFee);
        vm.stopPrank();
    }

    /* ========== LOGS ========== */

    event FactoryChanged(address indexed factory, bool indexed isOn);
    event SpaceFactoryChanged(address oldSpaceFactory, address newSpaceFactory);
    // event PoolManagerChanged(address oldPoolManager, address newPoolManager);
    event SeriesSponsored(address indexed adapter, uint256 indexed maturity, address indexed sponsor);
    event AdapterDeployed(address indexed adapter);
    event AdapterOnboarded(address indexed adapter);
    event AdapterVerified(address indexed adapter);
    event Swapped(
        address indexed sender,
        bytes32 indexed poolId,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes4 indexed sig
    );
    event PTRedeemed(address indexed adapter, uint256 indexed maturity, uint256 redeemed);

    // Pool Manager
    event TargetAdded(address indexed target, address indexed cTarget);
    event SeriesQueued(address indexed adapter, uint256 indexed maturity, address indexed pool);
}
