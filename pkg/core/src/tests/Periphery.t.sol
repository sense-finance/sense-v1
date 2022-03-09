// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../external/FixedMath.sol";
import { Periphery } from "../Periphery.sol";
import { Token } from "../tokens/Token.sol";
import { PoolManager, ComptrollerLike } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
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
        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);

        // check pt and yield deployed
        assertTrue(pt != address(0));
        assertTrue(yield != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and yields onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testSponsorSeriesWhenUnverifiedAdapter() public {
        divider.setPermissionless(true);
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            1e18,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.addAdapter(address(adapter));

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = alice.doSponsorSeries(address(adapter), maturity);

        // check pt and yield deployed
        assertTrue(pt != address(0));
        assertTrue(yield != address(0));

        // check Space pool is deployed
        assertTrue(address(spaceFactory.pool()) != address(0));

        // check pt and yields NOT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.NONE);
    }

    function testSponsorSeriesWhenUnverifiedAdapterAndWithPoolFalse() public {
        divider.setPermissionless(true);
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            1e18,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        divider.addAdapter(address(adapter));

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = alice.doSponsorSeriesWithoutPool(address(adapter), maturity);

        // check pt and yield deployed
        assertTrue(pt != address(0));
        assertTrue(yield != address(0));

        // check Space pool is NOT deployed
        assertTrue(address(spaceFactory.pool()) == address(0));

        // check pt and yields NOT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(address(poolManager)).sSeries(address(adapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.NONE);
    }

    function testDeployAdapter() public {
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockToken newTarget = new MockTarget(address(underlying), "New Target", "NT", 18);
        factory.addTarget(address(newTarget), true);

        // onboard target
        address adapter = periphery.deployAdapter(address(factory), address(newTarget));
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        assertTrue(cTarget != address(0));
    }

    function testDeployAdapterWhenPermissionless() public {
        divider.setPermissionless(true);
        // add a new target to the factory supported targets
        MockToken underlying = new MockToken("New Underlying", "NT", 18);
        MockToken newTarget = new MockTarget(address(underlying), "New Target", "NT", 18);
        factory.addTarget(address(newTarget), true);

        // onboard target
        periphery.deployAdapter(address(factory), address(newTarget));
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(newTarget));
        assertTrue(cTarget != address(0));
    }

    function testCantDeployAdapterIfTargetIsNotSupportedOnSpecificAdapter() public {
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget someTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        MockFactory someFactory = createFactory(address(someTarget), address(someReward));
        try periphery.deployAdapter(address(factory), address(someTarget)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        }
        periphery.deployAdapter(address(someFactory), address(someTarget));
    }

    function testCantDeployAdapterIfTargetIsNotSupported() public {
        MockToken someUnderlying = new MockToken("Some Underlying", "SU", 18);
        MockTarget newTarget = new MockTarget(address(someUnderlying), "Some Target", "ST", 18);
        try periphery.deployAdapter(address(factory), address(newTarget)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetNotSupported.selector));
        }
    }

    function testOnboardAdapterVerified() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTarget otherTarget = new MockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18);
        MockAdapter otherAdapter = new MockAdapter(
            address(divider),
            address(otherTarget),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            4,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        periphery.verifyAdapter(address(otherAdapter), true);
        periphery.onboardAdapter(address(otherAdapter));
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(otherTarget));
        assertTrue(cTarget != address(0));
    }

    function testOnboardAdapterUnverified() public {
        divider.setPermissionless(true);
        periphery.setIsTrusted(address(this), false);
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTarget otherTarget = new MockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18);
        MockAdapter otherAdapter = new MockAdapter(
            address(divider),
            address(otherTarget),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            4,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );

        periphery.onboardAdapter(address(otherAdapter));
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(otherTarget));
        assertTrue(cTarget != address(0));
    }

    function testCantOnboardAdapterUnverifiedWhenNotPermissionless() public {
        MockToken otherUnderlying = new MockToken("Usdc", "USDC", 18);
        MockTarget otherTarget = new MockTarget(address(otherUnderlying), "Compound Usdc", "cUSDC", 18);
        periphery.setIsTrusted(address(this), false);
        MockAdapter otherAdapter = new MockAdapter(
            address(divider),
            address(otherTarget),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            4,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );
        periphery.onboardAdapter(address(otherAdapter));
        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(otherTarget));
        assertTrue(cTarget != address(0));
    }

    /* ========== swap tests ========== */

    function testswapTargetForPTs() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(yield).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // unwrap target into underlying
        (, uint256 lvalue) = adapter.lscale();
        uint256 uBal = tBal.fmul(lvalue, FixedMath.WAD);

        // calculate underlying swapped to pt
        uint256 zBal = uBal.fdiv(balancerVault.EXCHANGE_RATE(), FixedMath.WAD);

        alice.doswapTargetForPTs(address(adapter), maturity, tBal, 0);

        assertEq(cBalBefore, ERC20(yield).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(pt).balanceOf(address(alice)));
    }

    function testSwapUnderlyingForPTs() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lvalue) = adapter.lscale();

        // unwrap target into underlying
        uint256 uBal = tBal.fmul(lvalue, FixedMath.WAD);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(yield).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // calculate underlying swapped to pt
        uint256 zBal = uBal.fdiv(balancerVault.EXCHANGE_RATE(), FixedMath.WAD);

        alice.doSwapUnderlyingForPTs(address(adapter), maturity, uBal, 0);

        assertEq(cBalBefore, ERC20(yield).balanceOf(address(alice)));
        assertEq(zBalBefore + zBal, ERC20(pt).balanceOf(address(alice)));
    }

    function testSwapTargetForYTs() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
        uint256 tBase = 10**target.decimals();

        // add liquidity to mockBalancerVault
        target.mint(address(adapter), 100000e18);
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(yield).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (adapter.ifee() / convertBase(target.decimals())).fmul(tBal, tBase);
        uint256 yieldsAmount = (tBal - fee).fmul(lscale, FixedMath.WAD);
        bob.doSwapTargetForYTs(address(adapter), maturity, tBal, 0);

        assertEq(cBalBefore + yieldsAmount, ERC20(yield).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(pt).balanceOf(address(alice)));
    }

    function testSwapUnderlyingForYTs() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
        uint256 tBase = 10**target.decimals();

        // unwrap target into underlying
        uint256 uBal = tBal.fmul(lscale, FixedMath.WAD);

        // add liquidity to mockBalancerVault
        target.mint(address(adapter), 100000e18);
        addLiquidityToBalancerVault(maturity, 1000e18);

        uint256 cBalBefore = ERC20(yield).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // calculate issuance fee in corresponding base
        uint256 fee = (adapter.ifee() / convertBase(target.decimals())).fmul(tBal, tBase);
        uint256 yieldsAmount = (tBal - fee).fmul(lscale, FixedMath.WAD);
        bob.doSwapUnderlyingForYTs(address(adapter), maturity, uBal, 0);

        assertEq(cBalBefore + yieldsAmount, ERC20(yield).balanceOf(address(bob)));
        assertEq(zBalBefore, ERC20(pt).balanceOf(address(alice)));
    }

    function testSwapPrincipalForTarget() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address pt, ) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        alice.doIssue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // calculate pt swapped to target
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 swapped = zBalBefore.fmul(rate, FixedMath.WAD);

        alice.doApprove(pt, address(periphery), zBalBefore);
        alice.doSwapPrincipalForTarget(address(adapter), maturity, zBalBefore, 0);

        assertEq(tBalBefore + swapped, ERC20(target).balanceOf(address(alice)));
    }

    function testSwapPrincipalForUnderlying() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);

        (address pt, ) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockBalancerVault
        addLiquidityToBalancerVault(maturity, 1000e18);

        alice.doIssue(address(adapter), maturity, tBal);

        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(address(alice));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(alice));

        // calculate pt swapped to target
        uint256 rate = balancerVault.EXCHANGE_RATE();
        uint256 swapped = zBalBefore.fmul(rate, FixedMath.WAD);

        // unwrap target into underlying
        (, uint256 lvalue) = adapter.lscale();
        uint256 uBal = swapped.fmul(lvalue, FixedMath.WAD);

        alice.doApprove(pt, address(periphery), zBalBefore);
        alice.doSwapPrincipalForUnderlying(address(adapter), maturity, zBalBefore, 0);

        assertEq(uBalBefore + uBal, ERC20(underlying).balanceOf(address(alice)));
    }

    function testSwapYieldForTarget() public {
        uint256 tBal = 100e18;
        uint256 targetToBorrow = 9.025e19;
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yield) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        bob.doIssue(address(adapter), maturity, tBal);

        uint256 tBalBefore = ERC20(target).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(yield).balanceOf(address(bob));

        // swap underlying for Principal on Yieldspace pool
        uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE(), FixedMath.WAD);

        // combine pt and yield
        uint256 tCombined = zSwapped.fdiv(lscale, FixedMath.WAD);
        uint256 remainingYTInTarget = tCombined - targetToBorrow;

        bob.doApprove(yield, address(periphery), cBalBefore);
        bob.doSwapYieldForTarget(address(adapter), maturity, cBalBefore);

        assertEq(tBalBefore + remainingYTInTarget, ERC20(target).balanceOf(address(bob)));
    }

    //    function testSwapYieldForTargetWithGap() public {
    //        uint256 tBal = 100e18;
    //        uint256 maturity = getValidMaturity(2021, 10);
    //
    //        (address pt, address yield) = sponsorSampleSeries(address(alice), maturity);
    //
    //        // add liquidity to mockUniSwapRouter
    //        addLiquidityToBalancerVault(maturity, 1000e18);
    //
    //        alice.doIssue(address(adapter), maturity, tBal);
    //        hevm.warp(block.timestamp + 5 days);
    //
    //        bob.doIssue(address(adapter), maturity, tBal);
    //
    //        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));
    //        uint256 cBalBefore = ERC20(yield).balanceOf(address(bob));
    //
    //        // calculate yields to be converted to gyields
    //        address gyield = address(periphery.gYTManager().gyields(yield));
    //        uint256 rate = periphery.price(pt, gyield);
    //        uint256 yieldsToConvert =
    //          cBalBefore.fdiv(rate + 1 * 10**ERC20(pt).decimals(), 10**ERC20(yield).decimals());
    //
    //        // calculate gyields swapped to pt
    //        uint256 swapped = yieldsToConvert.fmul(uniSwapRouter.EXCHANGE_RATE(), 10**ERC20(pt).decimals());
    //
    //        // calculate target to receive after combining
    //        uint256 lscale = divider.lscales(address(adapter), maturity, address(bob));
    //        uint256 tCombined = swapped.fdiv(lscale, 10**ERC20(yield).decimals());
    //
    //        // calculate excess
    //        uint256 excess = periphery.gYTManager().excess(address(adapter), maturity, yieldsToConvert);
    //
    //        bob.doApprove(yield, address(periphery), cBalBefore);
    //        bob.doSwapYieldForTarget(address(adapter), maturity, cBalBefore, 0);
    //
    //        assertEq(tBalBefore + tCombined - excess, ERC20(target).balanceOf(address(bob)));
    //    }

    /* ========== liquidity tests ========== */
    function testAddLiquidityFirstTimeWithSellYieldModeShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(targetBal, 0);
        assertEq(yieldBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityFirstTimeWithHoldYieldModeShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            1
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(targetBal, 0);
        assertEq(yieldBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        // init liquidity
        alice.doAddLiquidityFromTarget(address(adapter), maturity, 1, 0);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(targetBal, 0);
        assertEq(yieldBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldYieldWith0_TargetRatioShouldNotIssue() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        // init liquidity
        alice.doAddLiquidityFromTarget(address(adapter), maturity, 1, 0);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            1
        );
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(targetBal, 0);
        assertEq(yieldBal, 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertEq(tBalBefore - tBal, tBalAfter);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndSellYT() public {
        uint256 tBal = 100e18;

        uint256 maturity = getValidMaturity(2021, 10);
        (address pt, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        alice.doAddLiquidityFromTarget(address(adapter), maturity, 1, 0);

        // calculate targetToBorrow
        uint256 targetToBorrow;
        {
            // compute target
            uint256 tBase = 10**target.decimals();
            uint256 principaliBal = ERC20(pt).balanceOf(address(balancerVault));
            uint256 targetiBal = target.balanceOf(address(balancerVault));
            uint256 computedTarget = tBal.fmul(
                principaliBal.fdiv(
                    adapter.scale().fmul(targetiBal).fmul(FixedMath.WAD - adapter.ifee()) + principaliBal,
                    tBase
                ),
                tBase
            ); // ABDK formula

            // to issue
            uint256 fee = computedTarget.fmul(adapter.ifee());
            uint256 toBeIssued = (computedTarget - fee).fmul(lscale, FixedMath.WAD);

            MockSpacePool pool = MockSpacePool(spaceFactory.pools(address(adapter), maturity));
            targetToBorrow = pool.onSwap(
                BalancerPool.SwapRequest({
                    kind: BalancerVault.SwapKind.GIVEN_OUT,
                    tokenIn: target,
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

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        // calculate target to borrow
        uint256 remainingYTInTarget;
        {
            // swap Target for Principal on Yieldspace pool
            uint256 zSwapped = targetToBorrow.fdiv(balancerVault.EXCHANGE_RATE(), FixedMath.WAD);
            // combine pt and yield
            uint256 tCombined = zSwapped.fdiv(lscale, FixedMath.WAD);
            remainingYTInTarget = tCombined - targetToBorrow;
        }

        (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
            address(adapter),
            maturity,
            tBal,
            0
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertTrue(targetBal > 0);
        assertTrue(yieldBal > 0);
        assertEq(lpShares, lpBalAfter - lpBalBefore);
        assertClose(tBalBefore - tBal + remainingYTInTarget, tBalAfter, 10);
        assertEq(lpBalBefore + 100e18, lpBalAfter);
    }

    function testAddLiquidityAndHoldYT() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (, address yield) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        alice.doAddLiquidityFromTarget(address(adapter), maturity, 1, 1);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(yield).balanceOf(address(bob));

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            // calculate yields to be issued
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            (, uint256 lscale) = adapter.lscale();
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(lscale.fmul(balances[0]).fmul(FixedMath.WAD - adapter.ifee()) + balances[1], tBase),
                tBase
            ); // ABDK formula

            uint256 fee = proportionalTarget.fmul(adapter.ifee());
            toBeIssued = (proportionalTarget - fee).fmul(lscale, FixedMath.WAD);
        }

        {
            (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromTarget(
                address(adapter),
                maturity,
                tBal,
                1
            );

            assertEq(targetBal, 0);
            assertTrue(yieldBal > 0);
            assertEq(lpShares, ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob)) - lpBalBefore);

            assertEq(tBalBefore - tBal, ERC20(adapter.target()).balanceOf(address(bob)));
            assertEq(lpBalBefore + 100e18, ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob)));
            assertEq(cBalBefore + toBeIssued, ERC20(yield).balanceOf(address(bob)));
        }
    }

    function testAddLiquidityFromUnderlyingAndHoldYT() public {
        uint256 tBal = 100e18; // we assume target = underlying as scale is 1e18
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (, address yield) = sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mock Space pool
        addLiquidityToBalancerVault(maturity, 1000e18);

        // init liquidity
        alice.doAddLiquidityFromTarget(address(adapter), maturity, 1, 1);

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 uBalBefore = ERC20(adapter.underlying()).balanceOf(address(bob));
        uint256 cBalBefore = ERC20(yield).balanceOf(address(bob));

        // calculate amount to be issued
        uint256 toBeIssued;
        {
            // calculate yields to be issued
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 scale = 1e18;
            uint256 proportionalTarget = tBal.fmul(
                balances[1].fdiv(scale.fmul(balances[0]).fmul(FixedMath.WAD - adapter.ifee()) + balances[1], tBase),
                tBase
            ); // ABDK formula

            (, uint256 lscale) = adapter.lscale();
            uint256 fee = adapter.ifee().fmul(proportionalTarget);
            toBeIssued = (proportionalTarget - fee).fmul(lscale);
        }

        {
            (uint256 targetBal, uint256 yieldBal, uint256 lpShares) = bob.doAddLiquidityFromUnderlying(
                address(adapter),
                maturity,
                tBal,
                1
            );

            assertEq(targetBal, 0);
            assertTrue(yieldBal > 0);
            assertEq(lpShares, ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob)) - lpBalBefore);

            assertEq(uBalBefore - tBal, ERC20(adapter.underlying()).balanceOf(address(bob)));
            assertEq(lpBalBefore + 100e18, ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob)));
            assertEq(cBalBefore + toBeIssued, ERC20(yield).balanceOf(address(bob)));
        }
    }

    function testRemoveLiquidityBeforeMaturity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = tBal *
                (balances[1] / ((1e18 * balances[0] * (FixedMath.WAD - adapter.ifee())) / FixedMath.WAD + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale, FixedMath.WAD);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale, FixedMath.WAD); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        // calculate liquidity added
        {
            // minAmountsOut to target
            uint256 uBal = minAmountsOut[1].fmul(balancerVault.EXCHANGE_RATE(), FixedMath.WAD); // pt to underlying
            tBal = (minAmountsOut[0] + uBal).fdiv(lscale, FixedMath.WAD); // (pt (in underlying) + underlying) to target
        }

        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBal);
        (uint256 targetBal, uint256 zBal) = bob.doremoveLiquidity(
            address(adapter),
            maturity,
            lpBal,
            minAmountsOut,
            0,
            true
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(targetBal, tBalAfter - tBalBefore);
        assertEq(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
        assertEq(zBal, 0);
    }

    function testRemoveLiquidityOnMaturity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        {
            // calculate pt to be issued when adding liquidity
            (, uint256[] memory balances, ) = balancerVault.getPoolTokens(0);
            uint256 proportionalTarget = tBal * (balances[1] / (1e18 * balances[0] + balances[1])); // ABDK formula
            uint256 fee = convertToBase(adapter.ifee(), target.decimals()).fmul(proportionalTarget, tBase);
            uint256 toBeIssued = (proportionalTarget - fee).fmul(lscale, FixedMath.WAD);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale, FixedMath.WAD); // underlying amount
            minAmountsOut[1] = toBeIssued; // pt to be issued
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);
        // settle series
        hevm.warp(maturity);
        alice.doSettleSeries(address(adapter), maturity);
        (, lscale) = adapter.lscale();

        uint256 zBalBefore = ERC20(pt).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBal);
        (uint256 targetBal, ) = bob.doremoveLiquidity(address(adapter), maturity, lpBal, minAmountsOut, 0, true);

        uint256 zBalAfter = ERC20(pt).balanceOf(address(bob));
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));

        assertEq(zBalBefore, zBalAfter);
        assertEq(targetBal, tBalAfter - tBalBefore);
        assertClose(tBalBefore + tBal, tBalAfter);
        assertEq(lpBalAfter, 0);
    }

    function testRemoveLiquidityOnMaturityAndPrincipalRedeemRestricted() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        // uint256 tBase = 10**target.decimals();

        // create adapter with principalRedeem restricted
        MockToken underlying = new MockToken("Usdc Token", "USDC", 18);
        MockTarget target = new MockTarget(address(underlying), "Compound USDC", "cUSDC", 18);

        divider.setPermissionless(true);
        uint16 level = 0x1 + 0x2 + 0x4 + 0x8; // redeem restricted
        MockAdapter aAdapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            level,
            address(reward)
        );

        periphery.verifyAdapter(address(aAdapter), true);
        periphery.onboardAdapter(address(aAdapter));
        divider.setGuard(address(aAdapter), 10 * 2**128);

        alice.doApprove(address(target), address(divider));
        bob.doApprove(address(target), address(periphery));
        alice.doMint(address(target), 10000000e18);
        bob.doMint(address(target), 10000000e18);

        (address pt, ) = alice.doSponsorSeries(address(aAdapter), maturity);
        address pool = spaceFactory.create(address(aAdapter), maturity);

        (, uint256 lscale) = aAdapter.lscale();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 2e18;
        minAmountsOut[1] = 1e18;

        addLiquidityToBalancerVault(address(aAdapter), maturity, 1000e18);

        bob.doAddLiquidityFromTarget(address(aAdapter), maturity, tBal, 1);

        // settle series
        hevm.warp(maturity);
        alice.doSettleSeries(address(aAdapter), maturity);
        (, lscale) = aAdapter.lscale();

        uint256 zBalBefore = ERC20(pt).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(aAdapter.target()).balanceOf(address(bob));

        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), 3e18);
        (uint256 targetBal, uint256 zBal) = bob.doremoveLiquidity(
            address(aAdapter),
            maturity,
            3e18,
            minAmountsOut,
            0,
            true
        );

        assertEq(targetBal, ERC20(aAdapter.target()).balanceOf(address(bob)) - tBalBefore);
        assertEq(zBalBefore, ERC20(pt).balanceOf(address(bob)) - minAmountsOut[1]);
        assertEq(zBal, ERC20(pt).balanceOf(address(bob)) - zBalBefore);
        assertEq(zBal, 1e18);
    }

    function testRemoveLiquidityWhenOneSideLiquidity() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
        uint256[] memory minAmountsOut = new uint256[](2);

        // add one side liquidity
        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);

        uint256 zBalBefore = ERC20(pt).balanceOf(address(bob));
        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));

        uint256 lpBalBefore = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBalBefore);
        (uint256 targetBal, uint256 zBal) = bob.doremoveLiquidity(
            address(adapter),
            maturity,
            lpBalBefore,
            minAmountsOut,
            0,
            true
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 zBalAfter = ERC20(pt).balanceOf(address(bob));

        assertTrue(tBalAfter > 0);
        assertEq(targetBal, tBalAfter - tBalBefore);
        assertEq(zBalAfter, zBalBefore);
        assertEq(lpBalAfter, 0);
        assertEq(zBal, 0);
        assertTrue(lpBalBefore > 0);
    }

    function testRemoveLiquidityAndSkipSwap() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        uint256 tBase = 10**target.decimals();
        (address pt, ) = sponsorSampleSeries(address(alice), maturity);
        (, uint256 lscale) = adapter.lscale();
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
            ptToBeIssued = (proportionalTarget - fee).fmul(lscale, FixedMath.WAD);

            // prepare minAmountsOut for removing liquidity
            minAmountsOut[0] = (tBal - proportionalTarget).fmul(lscale, FixedMath.WAD); // underlying amount
            minAmountsOut[1] = ptToBeIssued; // pt to be issued
        }

        bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 1);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 zBalBefore = ERC20(pt).balanceOf(address(bob));

        uint256 lpBal = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        bob.doApprove(address(balancerVault.yieldSpacePool()), address(periphery), lpBal);
        (uint256 targetBal, uint256 zBal) = bob.doremoveLiquidity(
            address(adapter),
            maturity,
            lpBal,
            minAmountsOut,
            0,
            false
        );

        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(bob));
        uint256 lpBalAfter = ERC20(balancerVault.yieldSpacePool()).balanceOf(address(bob));
        uint256 zBalAfter = ERC20(pt).balanceOf(address(bob));

        assertEq(tBalAfter, tBalBefore + targetBal);
        assertEq(lpBalAfter, 0);
        assertEq(zBal, ptToBeIssued);
        assertEq(zBalAfter, zBalBefore + ptToBeIssued);
    }

    function testCantMigrateLiquidityIfTargetsAreDifferent() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);

        // add liquidity to mockUniSwapRouter
        addLiquidityToBalancerVault(maturity, 1000e18);

        MockTarget otherTarget = new MockTarget(address(underlying), "Compound Usdc", "cUSDC", 8);
        factory.addTarget(address(otherTarget), true);
        address dstAdapter = periphery.deployAdapter(address(factory), address(otherTarget)); // onboard target through Periphery

        (, , uint256 lpShares) = bob.doAddLiquidityFromTarget(address(adapter), maturity, tBal, 0);
        uint256[] memory minAmountsOut = new uint256[](2);
        try
            bob.doMigrateLiquidity(
                address(adapter),
                dstAdapter,
                maturity,
                maturity,
                lpShares,
                minAmountsOut,
                0,
                0,
                true
            )
        {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetMismatch.selector));
        }
    }

    function testMigrateLiquidity() public {
        // TODO!
    }

    function testQuotePrice() public {
        // TODO!
    }
}
