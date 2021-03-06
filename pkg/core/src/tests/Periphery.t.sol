// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { PoolManager, ComptrollerLike } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { TestHelper, MockTargetLike } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockFactory, Mock4626CropFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockPoolManager } from "./test-helpers/mocks/MockPoolManager.sol";
import { MockSpacePool } from "./test-helpers/mocks/MockSpace.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BalancerPool } from "../external/balancer/Pool.sol";
import { BalancerVault } from "../external/balancer/Vault.sol";

contract PeripheryTest is TestHelper {
    using FixedMath for uint256;

    function testDeployPeriphery() public {
        MockPoolManager poolManager = new MockPoolManager();
        address spaceFactory = address(2);
        address balancerVault = address(3);
        Periphery somePeriphery = new Periphery(address(divider), address(poolManager), spaceFactory, balancerVault);
        assertTrue(address(somePeriphery) != address(0));
        assertEq(address(Periphery(somePeriphery).divider()), address(divider));
        assertEq(address(Periphery(somePeriphery).poolManager()), address(poolManager));
        assertEq(address(Periphery(somePeriphery).spaceFactory()), address(spaceFactory));
        assertEq(address(Periphery(somePeriphery).balancerVault()), address(balancerVault));
    }

    function testSponsorSeries() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and YTs onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testSponsorSeriesWhenUnverifiedAdapter() public {
        divider.setPermissionless(true);
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            !is4626 ? target.underlying() : target.asset(),
            ISSUANCE_FEE,
            DEFAULT_ADAPTER_PARAMS,
            address(reward)
        );

        divider.addAdapter(address(adapter));

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and YTs NOT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.NONE);
    }

    function testSponsorSeriesWhenUnverifiedAdapterAndWithPoolFalse() public {
        divider.setPermissionless(true);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: ORACLE,
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            !is4626 ? target.underlying() : target.asset(),
            ISSUANCE_FEE,
            adapterParams,
            address(reward)
        );

        divider.addAdapter(address(adapter));

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, false);

        // check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // check Space pool is NOT deployed
        assertTrue(address(spaceFactory.pool()) == address(0));

        // check pt and YTs NOT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.NONE);
    }

    function testDeployAdapter() public {
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));

        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.deployAdapter(address(factory), address(newTarget), "");
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        assertTrue(cTarget != address(0));
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
            tilt: 0
        });

        address cropFactory;
        if (is4626) {
            cropFactory = address(new Mock4626CropFactory(address(divider), factoryParams, address(reward)));
        } else {
            cropFactory = address(new MockFactory(address(divider), factoryParams, address(reward)));
        }
        divider.setIsTrusted(cropFactory, true);
        periphery.setFactory(cropFactory, true);

        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));
        MockFactory(cropFactory).addTarget(address(newTarget), true);

        // onboard target
        periphery.deployAdapter(cropFactory, address(newTarget), "");
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        assertTrue(cTarget != address(0));
    }

    function testDeployAdapterWhenPermissionless() public {
        divider.setPermissionless(true);
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(underlying), "New Target", "NT", 18));
        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.deployAdapter(address(factory), address(newTarget), "");
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        assertTrue(cTarget != address(0));
    }

    function testCantDeployAdapterIfTargetIsNotSupportedOnSpecificAdapter() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTargetLike someTarget = MockTargetLike(deployMockTarget(address(someUnderlying), "Some Target", "ST", 18));
        MockFactory someFactory = MockFactory(deployFactory(address(someTarget), address(reward)));

        // try deploying adapter using default factory
        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        periphery.deployAdapter(address(factory), address(someTarget), "");

        // try deploying adapter using new factory with supported target
        periphery.deployAdapter(address(someFactory), address(someTarget), "");
    }

    function testCantDeployAdapterIfTargetIsNotSupported() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTargetLike newTarget = MockTargetLike(deployMockTarget(address(someUnderlying), "Some Target", "ST", 18));
        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        periphery.deployAdapter(address(factory), address(newTarget), "");
    }

    /* ========== admin update storage addresses ========== */

    event PoolManagerChanged(address, address);

    function testUpdatePoolManager() public {
        address oldPoolManager = address(periphery.poolManager());

        hevm.record();
        address NEW_POOL_MANAGER = address(0xbabe);

        // Expect the new Pool Manager to be set, and for a "change" event to be emitted
        hevm.expectEmit(false, false, false, true);
        emit PoolManagerChanged(oldPoolManager, NEW_POOL_MANAGER);

        // 1. Update the Pool Manager address
        periphery.setPoolManager(NEW_POOL_MANAGER);
        (, bytes32[] memory writes) = hevm.accesses(address(periphery));

        // Check that the storage slot was updated correctly
        assertEq(address(periphery.poolManager()), NEW_POOL_MANAGER);
        // Check that only one storage slot was written to
        assertEq(writes.length, 1);
    }

    event SpaceFactoryChanged(address, address);

    function testUpdateSpaceFactory() public {
        address oldSpaceFactory = address(periphery.spaceFactory());

        hevm.record();
        address NEW_SPACE_FACTORY = address(0xbabe);

        // Expect the new Space Factory to be set, and for a "change" event to be emitted
        hevm.expectEmit(false, false, false, true);
        emit SpaceFactoryChanged(oldSpaceFactory, NEW_SPACE_FACTORY);

        // 1. Update the Space Factory address
        periphery.setSpaceFactory(NEW_SPACE_FACTORY);
        (, bytes32[] memory writes) = hevm.accesses(address(periphery));

        // Check that the storage slot was updated correctly
        assertEq(address(periphery.spaceFactory()), NEW_SPACE_FACTORY);
        // Check that only one storage slot was written to
        assertEq(writes.length, 1);
    }

    function testFuzzUpdatePoolManager(address lad) public {
        hevm.record();
        hevm.assume(lad != alice); // For any address other than the testing contract
        address NEW_POOL_MANAGER = address(0xbabe);

        // 1. Impersonate the fuzzed address and try to update the Pool Manager address
        hevm.prank(lad);
        hevm.expectRevert("UNTRUSTED");
        periphery.setPoolManager(NEW_POOL_MANAGER);

        (, bytes32[] memory writes) = hevm.accesses(address(periphery));
        // Check that only no storage slots were written to
        assertEq(writes.length, 0);
    }

    function testFuzzUpdateSpaceFactory(address lad) public {
        hevm.record();
        hevm.assume(lad != alice); // For any address other than the testing contract
        address NEW_SPACE_FACTORY = address(0xbabe);

        // 1. Impersonate the fuzzed address and try to update the Space Factory address
        hevm.prank(lad);
        hevm.expectRevert("UNTRUSTED");
        periphery.setSpaceFactory(NEW_SPACE_FACTORY);

        (, bytes32[] memory writes) = hevm.accesses(address(periphery));
        // Check that only no storage slots were written to
        assertEq(writes.length, 0);
    }

    /* ========== admin onboarding tests ========== */

    function testAdminOnboardVerifiedAdapter() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.verifyAdapter(address(otherAdapter), true);
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
        periphery.verifyAdapter(address(otherAdapter), true);
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
        periphery.verifyAdapter(address(otherAdapter), true); // admin verification
        periphery.setIsTrusted(alice, false);

        hevm.expectRevert(abi.encodeWithSelector(Errors.OnlyPermissionless.selector));
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

        hevm.expectRevert(abi.encodeWithSelector(Errors.OnlyPermissionless.selector));
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
        periphery.verifyAdapter(address(otherAdapter), true); // admin verification
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
            address(poolManager),
            address(spaceFactory),
            address(balancerVault)
        );
        somePeriphery.onboardAdapter(address(adapter), false);

        assertTrue(periphery.verified(address(adapter)));

        (, bool enabled, , ) = divider.adapterMeta(address(adapter));
        assertTrue(enabled);

        // try sponsoring
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
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
        periphery.verifyAdapter(address(otherAdapter), true); // admin verification
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
        periphery.verifyAdapter(address(otherAdapter), true); // admin verification
        assertTrue(periphery.verified(address(otherAdapter)));
    }

    function testCantVerifyAdapterNonAdmin() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTargetLike otherTarget = MockTargetLike(
            deployMockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18)
        );
        MockAdapter otherAdapter = MockAdapter(
            deployMockAdapter(address(divider), address(otherTarget), address(reward))
        );
        periphery.setIsTrusted(alice, false);
        hevm.expectRevert("UNTRUSTED");
        periphery.verifyAdapter(address(otherAdapter), true); // non-admin verification
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
        hevm.expectRevert("UNTRUSTED");
        periphery.verifyAdapter(address(otherAdapter), true); // non-admin verification
        assertTrue(!periphery.verified(address(otherAdapter)));
    }

    /* ========== swap tests ========== */

    function testSwapTargetForPTs() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 ytBalBefore = ERC20(yt).balanceOf(alice);
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);

        // unwrap target into underlying
        uint256 uBal = tBal.fmul(adapter.scale());

        // calculate underlying swapped to pt
        uint256 ptBal = uBal.fdiv(balancerVault.EXCHANGE_RATE());

        periphery.swapTargetForPTs(address(adapter), maturity, tBal, 0);

        assertEq(ytBalBefore, ERC20(yt).balanceOf(alice));
        assertEq(ptBalBefore + ptBal, ERC20(pt).balanceOf(alice));
    }

    function testSwapUnderlyingForPTs() public {
        uint256 uBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 scale = adapter.scale();

        // wrap underlying into target
        uint256 tBal = underlying.decimals() > target.decimals()
            ? uBal.fmul(scale) / SCALING_FACTOR
            : uBal.fmul(scale) * SCALING_FACTOR;

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 100000e18);

        uint256 ytBalBefore = ERC20(yt).balanceOf(alice);
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);

        // calculate underlying swapped to pt
        uint256 ptBal = tBal.fdiv(balancerVault.EXCHANGE_RATE());

        periphery.swapUnderlyingForPTs(address(adapter), maturity, uBal, 0);

        assertEq(ytBalBefore, ERC20(yt).balanceOf(alice));
        assertEq(ptBalBefore + ptBal, ERC20(pt).balanceOf(alice));
    }

    function testSwapPTsForTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        divider.issue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);

        // calculate pt swapped to target
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 swapped = ptBalBefore.fmul(rate);

        ERC20(pt).approve(address(periphery), ptBalBefore);

        periphery.swapPTsForTarget(address(adapter), maturity, ptBalBefore, 0);

        assertEq(tBalBefore + swapped, target.balanceOf(alice));
    }

    function testSwapPTsForUnderlying() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        divider.issue(address(adapter), maturity, tBal);

        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(alice);
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);

        // calculate pt swapped to target
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 swapped = ptBalBefore.fmul(rate);

        // unwrap target into underlying
        uint256 scale = adapter.scale();
        uint256 uBal = underlying.decimals() > target.decimals()
            ? swapped.fmul(scale) * SCALING_FACTOR
            : swapped.fmul(scale) / SCALING_FACTOR;

        ERC20(pt).approve(address(periphery), ptBalBefore);
        periphery.swapPTsForUnderlying(address(adapter), maturity, ptBalBefore, 0);

        assertEq(uBalBefore + uBal, ERC20(underlying).balanceOf(alice));
    }

    function testSwapYTsForTarget() public {
        uint256 tBal = 100e18;
        uint256 targetToBorrow = 9.025e19;
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 lscale = adapter.scale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, tBal);

        uint256 tBalBefore = target.balanceOf(bob);
        uint256 ytBalBefore = ERC20(yt).balanceOf(bob);

        // swap underlying for PT on Yieldspace pool
        uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE());

        // combine pt and yt
        uint256 tCombined = zSwapped.fdiv(lscale);
        uint256 remainingYTInTarget = tCombined - targetToBorrow;

        hevm.prank(bob);
        ERC20(yt).approve(address(periphery), ytBalBefore);
        hevm.prank(bob);
        periphery.swapYTsForTarget(address(adapter), maturity, ytBalBefore);

        assertEq(tBalBefore + remainingYTInTarget, target.balanceOf(bob));
    }

    /* ========== liquidity tests ========== */
    function testAddLiquidityFirstTimeWithSellYieldModeShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        hevm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0,
            type(uint256).max
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityFirstTimeWithHoldYieldModeShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        hevm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            1,
            type(uint256).max
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        // init liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, 1, 0, type(uint256).max);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        hevm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0,
            type(uint256).max
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        // init liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, 1, 0, type(uint256).max);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        hevm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            1,
            type(uint256).max
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertEq(targetBal, 0);
        assertEq(ytBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYT() public {
        uint256 tBal = 100e18;

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 lscale = adapter.scale();

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, 1, 0, type(uint256).max);

        // calculate targetToBorrow
        uint256 targetToBorrow;
        {
            // compute target
            uint256 tBase = 10**target.decimals();
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

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        // calculate target to borrow
        uint256 remainingYTInTarget;
        {
            // swap Target for PT on Yieldspace pool
            uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE());
            // combine pt and yt
            uint256 tCombined = zSwapped.fdiv(lscale);
            remainingYTInTarget = tCombined - targetToBorrow;
        }

        hevm.prank(bob);
        (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0,
            type(uint256).max
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertTrue(targetBal > 0);
        assertTrue(ytBal > 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertClose(tBalBefore - tBal + remainingYTInTarget, tBalAfter, 10);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldYT() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, 1, 1, type(uint256).max);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);
        uint256 ytBalBefore = ERC20(yt).balanceOf(bob);

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            // calculate YTs to be issued
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 scale = adapter.scale();
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(scale.fmul(balances[0]).fmul(FixedMath.WAD - adapter.ifee()) + balances[1], tBase),
                tBase
            ); // ABDK formula

            uint256 fee = proportionalTarget.fmul(adapter.ifee());
            toBeIssued = (proportionalTarget - fee).fmul(scale);
        }

        {
            hevm.prank(bob);
            (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromTarget(
                address(adapter),
                maturity,
                tBal,
                1,
                type(uint256).max
            );

            assertEq(targetBal, 0);
            assertTrue(ytBal > 0);
            assertEq(lpShares, ERC20(balancerVault.yieldSpacePool()).balanceOf(bob) - lpBalBefore);

            assertEq(tBalBefore - tBal, ERC20(adapter.target()).balanceOf(bob));
            assertEq(lpBalBefore + 100e18, ERC20(balancerVault.yieldSpacePool()).balanceOf(bob));
            assertEq(ytBalBefore + toBeIssued, ERC20(yt).balanceOf(bob));
        }
    }

    function testAddLiquidityFromUnderlyingAndHoldYT() public {
        uint256 uBal = 100e18; // we assume target = underlying as scale is 1e18
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, 1, 1, type(uint256).max);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);
        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(bob);
        uint256 ytBalBefore = ERC20(yt).balanceOf(bob);

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            uint256 lscale = adapter.scale();
            // calculate YTs to be issued
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);

            // wrap underlying into target
            uint256 tBal = underlying.decimals() > target.decimals()
                ? uBal.fdivUp(lscale) / SCALING_FACTOR
                : uBal.fdivUp(lscale) * SCALING_FACTOR;

            // calculate proportional target to add to pool
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(FixedMath.WAD - adapter.ifee()).fmul(balances[0]) + balances[1])
            ); // ABDK formula

            // calculate amount of target to issue
            uint256 fee = uint256(adapter.ifee()).fmul(proportionalTarget);
            toBeIssued = (proportionalTarget - fee).fmul(lscale);
        }

        {
            hevm.prank(bob);
            (uint256 targetBal, uint256 ytBal, uint256 lpShares) = periphery.addLiquidityFromUnderlying(
                address(adapter),
                maturity,
                uBal,
                1,
                type(uint256).max
            );

            assertEq(targetBal, 0);
            assertTrue(ytBal > 0);
            assertEq(lpShares, ERC20(balancerVault.yieldSpacePool()).balanceOf(bob) - lpBalBefore);

            assertEq(uBalBefore - uBal, ERC20(adapter.underlying()).balanceOf(bob));
            assertEq(lpBalBefore + 100e18, ERC20(balancerVault.yieldSpacePool()).balanceOf(bob));
            assertEq(toBeIssued, ytBal);
            assertEq(ytBalBefore + toBeIssued, ERC20(yt).balanceOf(bob));
        }
    }

    function testRemoveLiquidityBeforeMaturity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = tBal *
                (balances[1] / ((1e18 * balances[0] * (FixedMath.WAD - adapter.ifee())) / FixedMath.WAD + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        hevm.startPrank(bob);
        periphery.addLiquidityFromTarget(address(adapter), maturity, tBal, 1, type(uint256).max);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(bob);

        // calculate liquidity added
        {
            // minAmountsOut to target
            uint256 uBal = minAmountsOut[1].fmul(balancerVault.EXCHANGE_RATE()); // pt to underlying
            tBal = (minAmountsOut[0] + uBal).fdiv(lscale); // (pt (in underlying) + underlying) to target
        }
        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        balancerVault.yieldSpacePool().approve(address(periphery), lpBal);
        (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
            address(adapter),
            maturity,
            lpBal,
            minAmountsOut,
            0,
            true
        );
        hevm.stopPrank();

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(bob);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(bob);

        assertEq(targetBal, tBalAfter - tBalBefore);
        assertEq(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
        assertEq(ptBal, 0);
    }

    function testRemoveLiquidityOnMaturity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = tBal * (balances[1] / (1e18 * balances[0] + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        periphery.addLiquidityFromTarget(address(adapter), maturity, tBal, 1, type(uint256).max);
        // settle series
        hevm.warp(maturity);
        divider.settleSeries(address(adapter), maturity);
        lscale = adapter.scale();

        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);
        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);

        balancerVault.yieldSpacePool().approve(address(periphery), lpBal);
        (uint256 targetBal, ) = periphery.removeLiquidity(address(adapter), maturity, lpBal, minAmountsOut, 0, true);

        uint256 ptBalAfter = ERC20(pt).balanceOf(alice);
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(alice);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);

        assertEq(ptBalBefore, ptBalAfter);
        assertEq(targetBal, tBalAfter - tBalBefore);
        assertClose(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
    }

    function testRemoveLiquidityOnMaturityAndPTRedeemRestricted() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        // create adapter with ptRedeem restricted
        MockToken underlying = new MockToken("Usdc Token", "USDC", 18);
        MockTargetLike target = MockTargetLike(deployMockTarget(address(underlying), "Compound USDC", "cUSDC", 18));

        divider.setPermissionless(true);
        uint16 level = 0x1 + 0x2 + 0x4 + 0x8; // redeem restricted
        DEFAULT_ADAPTER_PARAMS.level = level;
        MockAdapter aAdapter = MockAdapter(deployMockAdapter(address(divider), address(target), address(reward)));

        periphery.verifyAdapter(address(aAdapter), true);
        periphery.onboardAdapter(address(aAdapter), true);
        divider.setGuard(address(aAdapter), 10 * 2**128);

        target.approve(address(divider), type(uint256).max);
        underlying.approve(address(target), type(uint256).max);

        hevm.startPrank(bob);
        target.approve(address(periphery), type(uint256).max);
        underlying.approve(address(target), type(uint256).max);
        hevm.stopPrank();

        // get some target for Alice and Bob
        if (!is4626) {
            target.mint(alice, 10000000e18);
            hevm.prank(bob);
            target.mint(bob, 10000000e18);
        } else {
            underlying.mint(alice, 10000000e18);
            underlying.mint(bob, 10000000e18);
            target.deposit(10000000e18, alice);
            hevm.prank(bob);
            target.deposit(10000000e18, bob);
        }

        (address pt, ) = periphery.sponsorSeries(address(aAdapter), maturity, true);
        spaceFactory.create(address(aAdapter), maturity);

        uint256 lscale = aAdapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 2e18;
        minAmountsOut[1] = 1e18;

        addLiquidityToBalancerVault(address(aAdapter), maturity, 1000e18);

        hevm.prank(bob);
        periphery.addLiquidityFromTarget(address(aAdapter), maturity, tBal, 1, type(uint256).max);

        // settle series
        hevm.warp(maturity);
        divider.settleSeries(address(aAdapter), maturity);
        lscale = aAdapter.scale();

        uint256 ptBalBefore = ERC20(pt).balanceOf(bob);
        uint256 tBalBefore = ERC20(aAdapter.target()).balanceOf(bob);

        hevm.startPrank(bob);
        balancerVault.yieldSpacePool().approve(address(periphery), 3e18);
        (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
            address(aAdapter),
            maturity,
            3e18,
            minAmountsOut,
            0,
            true
        );
        hevm.stopPrank();

        assertEq(targetBal, ERC20(aAdapter.target()).balanceOf(bob) - tBalBefore);
        assertEq(ptBalBefore, ERC20(pt).balanceOf(bob) - minAmountsOut[1]);
        assertEq(ptBal, ERC20(pt).balanceOf(bob) - ptBalBefore);
        assertEq(ptBal, 1e18);
    }

    function testRemoveLiquidityWhenOneSideLiquidity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256[] memory minAmountsOut = new uint256[](2);

        // add one side liquidity
        periphery.addLiquidityFromTarget(address(adapter), maturity, tBal, 1, type(uint256).max);

        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);
        balancerVault.yieldSpacePool().approve(address(periphery), lpBalBefore);
        (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
            address(adapter),
            maturity,
            lpBalBefore,
            minAmountsOut,
            0,
            true
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(alice);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);
        uint256 ptBalAfter = ERC20(pt).balanceOf(alice);

        assertTrue(tBalAfter > 0);
        assertEq(targetBal, tBalAfter - tBalBefore);
        assertEq(ptBalAfter, ptBalBefore);
        assertEq(lpBalAfter, 0);
        assertEq(ptBal, 0);
        assertTrue(lpBalBefore > 0);
    }

    function testRemoveLiquidityAndSkipSwap() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = periphery.sponsorSeries(address(adapter), maturity, true);
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 ptToBeIssued;
        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 fee = adapter.ifee();
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(FixedMath.WAD - fee).fmul(balances[0]) + balances[1], tBase),
                tBase
            );
            ptToBeIssued = (proportionalTarget - fee).fmul(lscale);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale); // underlying amount
            minAmountsOut[1] = ptToBeIssued; // pt to be issued
        }

        periphery.addLiquidityFromTarget(address(adapter), maturity, tBal, 1, type(uint256).max);
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(alice);
        uint256 ptBalBefore = ERC20(pt).balanceOf(alice);
        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);
        balancerVault.yieldSpacePool().approve(address(periphery), lpBal);
        (uint256 targetBal, uint256 ptBal) = periphery.removeLiquidity(
            address(adapter),
            maturity,
            lpBal,
            minAmountsOut,
            0,
            false
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(alice);
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);
        uint256 ptBalAfter = ERC20(pt).balanceOf(alice);

        assertEq(tBalAfter, tBalBefore + targetBal);
        assertEq(lpBalAfter, 0);
        assertEq(ptBal, ptToBeIssued);
        assertEq(ptBalAfter, ptBalBefore + ptToBeIssued);
    }

    function testRemoveLiquidityAndUnwrapTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        periphery.sponsorSeries(address(adapter), maturity, true);
        hevm.warp(block.timestamp + 5 days);
        uint256 lscale = adapter.scale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 ptToBeIssued;
        uint256 targetToBeAdded;
        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 fee = adapter.ifee();
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(FixedMath.WAD - fee).fmul(balances[0]) + balances[1], tBase),
                tBase
            );
            ptToBeIssued = (proportionalTarget - fee).fmul(lscale);
            targetToBeAdded = (tBal - proportionalTarget); // target amount
            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = targetToBeAdded;
            minAmountsOut[1] = ptToBeIssued; // pt to be issued
        }

        periphery.addLiquidityFromTarget(address(adapter), maturity, tBal, 1, type(uint256).max);
        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(alice);
        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(alice);
        balancerVault.yieldSpacePool().approve(address(periphery), lpBal);
        (uint256 underlyingBal, uint256 ptBal) = periphery.removeLiquidityAndUnwrapTarget(
            address(adapter),
            maturity,
            lpBal,
            minAmountsOut,
            0,
            false
        );

        uint256 uBalAfter = ERC20(adapter.underlying()).balanceOf(alice);
        assertEq(ERC20(balancerVault.yieldSpacePool()).balanceOf(alice), 0);
        assertEq(ptBal, ptToBeIssued);
        assertEq(uBalBefore + underlyingBal, uBalAfter);
        assertEq(
            underlyingBal,
            underlying.decimals() > target.decimals()
                ? targetToBeAdded.fmul(lscale) * SCALING_FACTOR
                : targetToBeAdded.fmul(lscale) / SCALING_FACTOR
        );
    }

    function testCantMigrateLiquidityIfTargetsAreDifferent() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        MockTargetLike otherTarget = MockTargetLike(deployMockTarget(address(underlying), "Compound Usdc", "cUSDC", 8));
        factory.addTarget(address(otherTarget), true);
        address dstAdapter = periphery.deployAdapter(address(factory), address(otherTarget), ""); // onboard target through Periphery

        (, , uint256 lpShares) = periphery.addLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0,
            type(uint256).max
        );
        uint256[] memory minAmountsOut = new uint256[](2);
        hevm.expectRevert(abi.encodeWithSelector(Errors.TargetMismatch.selector));
        periphery.migrateLiquidity(
            address(adapter),
            dstAdapter,
            maturity,
            maturity,
            lpShares,
            minAmountsOut,
            0,
            0,
            true,
            type(uint256).max
        );
    }

    function testMigrateLiquidity() public {
        // TODO!
    }

    function testQuotePrice() public {
        // TODO!
    }
}
