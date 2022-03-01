// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { FixedMath } from "./external/FixedMath.sol";
import { BalancerVault, IAsset } from "./external/balancer/Vault.sol";
import { BalancerPool } from "./external/balancer/Pool.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Levels } from "@sense-finance/v1-utils/src/libs/Levels.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";
import { BaseFactory as AdapterFactory } from "./adapters/BaseFactory.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";

interface SpaceFactoryLike {
    function create(address, uint256) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);
}

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;
    using Levels for uint256;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    Divider public immutable divider;

    /// @notice Sense core Divider address
    PoolManager public immutable poolManager;

    /// @notice Sense core Divider address
    SpaceFactoryLike public immutable spaceFactory;

    /// @notice Sense core Divider address
    BalancerVault public immutable balancerVault;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    /// @notice adapter factories -> is supported
    mapping(address => bool) public factories;

    /// @notice adapter -> bool
    mapping(address => bool) public verified;

    /* ========== DATA STRUCTURES ========== */

    struct PoolLiquidity {
        ERC20[] tokens;
        uint256[] amounts;
    }

    constructor(
        address _divider,
        address _poolManager,
        address _spaceFactory,
        address _balancerVault
    ) Trust(msg.sender) {
        divider = Divider(_divider);
        poolManager = PoolManager(_poolManager);
        spaceFactory = SpaceFactoryLike(_spaceFactory);
        balancerVault = BalancerVault(_balancerVault);
    }

    /* ========== SERIES / ADAPTER MANAGEMENT ========== */

    /// @notice Sponsor a new Series
    /// @dev Calls divider to initalise a new series
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    /// @param withPool Whether to deploy a Space pool or not (only works for unverified adapters)
    function sponsorSeries(
        address adapter,
        uint256 maturity,
        bool withPool
    ) external returns (address principal, address yield) {
        (, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();

        // Transfer stakeSize from sponsor into this contract
        ERC20(stake).safeTransferFrom(msg.sender, address(this), stakeSize);

        // Approve divider to withdraw stake assets
        ERC20(stake).approve(address(divider), stakeSize);

        (principal, yield) = divider.initSeries(adapter, maturity, msg.sender);

        // Space pool is always created for verified adapters whilst is optional for unverified ones.
        // Automatically queueing series is only for verified adapters
        if (verified[adapter]) {
            poolManager.queueSeries(adapter, maturity, spaceFactory.create(adapter, maturity));
        } else {
            if (withPool) {
                spaceFactory.create(adapter, maturity);
            }
        }
        emit SeriesSponsored(adapter, maturity, msg.sender);
    }

    /// @notice Deploy and onboard an Adapter
    /// @dev Deploys a new Adapter via an Adapter Factory
    /// @param f Factory to use
    /// @param target Target to onboard
    function deployAdapter(address f, address target) external returns (address adapter) {
        if (!factories[f]) revert Errors.FactoryNotSupported();
        if (!AdapterFactory(f).exists(target)) revert Errors.TargetNotSupported();
        adapter = AdapterFactory(f).deployAdapter(target);
        emit AdapterDeployed(adapter);
        verifyAdapter(adapter, true);
        onboardAdapter(adapter);
    }

    /// @dev Onboards an Adapter
    /// @dev Onboards Adapter's target onto Fuse if called from a trusted address
    /// @param adapter Adaper to onboard
    function onboardAdapter(address adapter) public {
        ERC20 target = ERC20(Adapter(adapter).target());
        target.approve(address(divider), type(uint256).max);
        target.approve(address(adapter), type(uint256).max);
        divider.addAdapter(adapter);
        emit AdapterOnboarded(adapter);
    }

    /* ========== LIQUIDITY UTILS ========== */

    /// @notice Swap Target to Principal of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    /// @param minAccepted Min accepted amount of Principal
    /// @return amount of Principal received
    function swapTargetForPrincipal(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal); // pull target
        return _swapTargetForPrincipal(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Underlying to Principal of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    /// @param minAccepted Min accepted amount of Principal
    /// @return amount of Principal received
    function swapUnderlyingForPrincipal(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20 underlying = ERC20(Adapter(adapter).underlying());
        underlying.safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        underlying.approve(adapter, uBal); // approve adapter to pull uBal
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        return _swapTargetForPrincipal(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Target to Yield of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    /// @param minAccepted Min accepted amount of Yield
    /// @return amount of Yield received
    function swapTargetForYield(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
        return _swapTargetForYield(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Underlying to Yield of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    /// @param minAccepted Min accepted amount of Yield
    /// @return amount of Yield received
    function swapUnderlyingForYield(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20 underlying = ERC20(Adapter(adapter).underlying());
        underlying.safeTransferFrom(msg.sender, address(this), uBal); // pull target
        underlying.approve(adapter, uBal); // approve adapter to pull underlying
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        return _swapTargetForYield(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Principal for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Principal to sell
    /// @param minAccepted Min accepted amount of Target
    function swapPrincipalForTarget(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _swapPrincipalForTarget(adapter, maturity, zBal, minAccepted); // swap principal for target
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal); // transfer target to msg.sender
        return tBal;
    }

    /// @notice Swap Principal for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Principal to sell
    /// @param minAccepted Min accepted amount of Target
    function swapPrincipalForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _swapPrincipalForTarget(adapter, maturity, zBal, minAccepted); // swap principal for target
        ERC20(Adapter(adapter).target()).approve(adapter, tBal); // approve adapter to pull target
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal); // unwrap target into underlying
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal); // transfer underlying to msg.sender
        return uBal;
    }

    /// @notice Swap Yield for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Yield to swap
    function swapYieldForTarget(
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) external returns (uint256) {
        uint256 tBal = _swapYieldForTarget(msg.sender, adapter, maturity, cBal);
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    /// @notice Swap Yield for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Yield to swap
    function swapYieldForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) external returns (uint256) {
        uint256 tBal = _swapYieldForTarget(msg.sender, adapter, maturity, cBal);
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal);
        return uBal;
    }

    /// @notice Adds liquidity providing target
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to provide
    /// @param mode 0 = issues and sell Yield, 1 = issue and hold Yield
    /// @return see return description of _addLiquidity
    function addLiquidityFromTarget(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint8 mode
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
        return _addLiquidity(adapter, maturity, tBal, mode);
    }

    /// @notice Adds liquidity providing underlying
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to provide
    /// @param mode 0 = issues and sell Yield, 1 = issue and hold Yield
    /// @return see return description of _addLiquidity
    function addLiquidityFromUnderlying(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint8 mode
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        ERC20 underlying = ERC20(Adapter(adapter).underlying());
        underlying.safeTransferFrom(msg.sender, address(this), uBal);
        underlying.approve(adapter, uBal);
        // Wrap Underlying into Target
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);
        return _addLiquidity(adapter, maturity, tBal, mode);
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns target
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut minimum accepted amounts of Principal and Target given the amount of LP shares provided
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Principal to underlying
    /// @return tBal amount of target received and zBal amount of principal (in case it's called after maturity and redeemPrincipal is restricted)
    function removeLiquidityToTarget(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external returns (uint256 tBal, uint256 zBal) {
        (tBal, zBal) = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal); // Send Target back to the User
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns underlying
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut minimum accepted amounts of Principal and Target given the amount of LP shares provided
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Principal to underlying
    /// @return uBal amount of underlying received and zBal principal (in case it's called after maturity and redeemPrincipal is restricted)
    function removeLiquidityToUnderlying(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external returns (uint256 uBal, uint256 zBal) {
        uint256 tBal;
        (tBal, zBal) = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).target()).approve(adapter, tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal = Adapter(adapter).unwrapTarget(tBal)); // Send Underlying back to the User
    }

    /// @notice Migrates liquidity position from one series to another
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param srcAdapter Adapter address for the source Series
    /// @param dstAdapter Adapter address for the destination Series
    /// @param srcMaturity Maturity date for the source Series
    /// @param dstMaturity Maturity date for the destination Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut Minimum accepted amounts of Principal and Target given the amount of LP shares provided
    /// @param minAccepted Min accepted amount of target when swapping Principal (only used when removing liquidity on/after maturity)
    /// @param mode 0 = issues and sell Yield, 1 = issue and hold Yield
    /// @notice see return description of _addLiquidity. It also returns amount of principal (in case it's called after maturity and redeemPrincipal is restricted)
    function migrateLiquidity(
        address srcAdapter,
        address dstAdapter,
        uint256 srcMaturity,
        uint256 dstMaturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        uint8 mode
    )
        external
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares,
            uint256 zBal
        )
    {
        if (Adapter(srcAdapter).target() != Adapter(dstAdapter).target()) revert Errors.TargetMismatch();
        uint256 tBal;
        (tBal, zBal) = _removeLiquidity(srcAdapter, srcMaturity, lpBal, minAmountsOut, minAccepted);
        (tAmount, issued, lpShares) = _addLiquidity(dstAdapter, dstMaturity, tBal, mode);
    }

    /* ========== ADMIN ========== */

    /// @notice Enable or disable a factory
    /// @param f Factory's address
    /// @param isOn Flag setting this factory to enabled or disabled
    function setFactory(address f, bool isOn) external requiresTrust {
        if (factories[f] == isOn) revert Errors.ExistingValue();
        factories[f] = isOn;
        emit FactoryChanged(f, isOn);
    }

    /// @dev Verifies an Adapter and optionally adds the Target to the money market
    /// @param adapter Adaper to verify
    function verifyAdapter(address adapter, bool addToPool) public requiresTrust {
        verified[adapter] = true;
        if (addToPool) poolManager.addTarget(Adapter(adapter).target(), adapter);
        emit AdapterVerified(adapter);
    }

    /* ========== INTERNAL UTILS ========== */

    function _swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 poolId,
        uint256 minAccepted
    ) internal returns (uint256 amountOut) {
        // approve vault to spend tokenIn
        ERC20(assetIn).approve(address(balancerVault), amountIn);

        BalancerVault.SingleSwap memory request = BalancerVault.SingleSwap({
            poolId: poolId,
            kind: BalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amountIn,
            userData: "0x" // TODO(launch): are we sure about this?
        });

        BalancerVault.FundManagement memory funds = BalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        amountOut = balancerVault.swap(request, funds, minAccepted, type(uint256).max);
        emit Swapped(msg.sender, poolId, assetIn, assetOut, amountIn, amountOut, msg.sig);
    }

    function _swapPrincipalForTarget(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        address principal = divider.principal(adapter, maturity);
        ERC20(principal).safeTransferFrom(msg.sender, address(this), zBal); // pull principal
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        return _swap(principal, Adapter(adapter).target(), zBal, pool.getPoolId(), minAccepted); // swap principal for underlying
    }

    function _swapTargetForPrincipal(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        address principal = divider.principal(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        uint256 zBal = _swap(Adapter(adapter).target(), principal, tBal, pool.getPoolId(), minAccepted); // swap target for principal
        ERC20(principal).safeTransfer(msg.sender, zBal); // transfer bought principal to user
        return zBal;
    }

    function _swapTargetForYield(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // issue principal and yields & swap principal for target
        uint256 issued = divider.issue(adapter, maturity, tBal);
        tBal = _swap(
            divider.principal(adapter, maturity),
            Adapter(adapter).target(),
            issued,
            pool.getPoolId(),
            minAccepted
        );

        // transfer yields & target to user
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        ERC20(divider.yield(adapter, maturity)).safeTransfer(msg.sender, issued);
        return issued;
    }

    function _swapYieldForTarget(
        address sender,
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) internal returns (uint256 tBal) {
        address yield = divider.yield(adapter, maturity);

        // Because there's some margin of error in the pricing functions here, smaller
        // swaps will be unreliable. Tokens with more than 18 decimals are not supported.
        if (cBal * 10**(18 - ERC20(yield).decimals()) <= 1e12) revert Errors.SwapTooSmall();
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // Transfer yields into this contract if needed
        if (sender != address(this)) ERC20(yield).safeTransferFrom(msg.sender, address(this), cBal);

        // Calculate target to borrow by calling AMM
        bytes32 poolId = pool.getPoolId();
        (uint256 principali, uint256 targeti) = pool.getIndices();
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolId);
        // Determine how much Target we'll need in to get `cBal` balance of Principal out
        // (space doesn't directly use of the fields from `SwapRequest` beyond `poolId`, so the values after are placeholders)
        uint256 targetToBorrow = BalancerPool(pool).onSwap(
            BalancerPool.SwapRequest({
                kind: BalancerVault.SwapKind.GIVEN_OUT,
                tokenIn: tokens[targeti],
                tokenOut: tokens[principali],
                amount: cBal,
                poolId: poolId,
                lastChangeBlock: 0,
                from: address(0),
                to: address(0),
                userData: ""
            }),
            balances[targeti],
            balances[principali]
        );

        // Flash borrow target (following actions in `onFlashLoan`)
        tBal = _flashBorrowAndSwap("0x", adapter, maturity, cBal, targetToBorrow);
    }

    /// @return tAmount if mode = 0, target received from selling Yield, otherwise, returns 0
    /// @return issued returns amount of Yield issued (and received) except first provision which returns 0
    /// @return lpShares Space LP shares received given the liquidity added
    function _addLiquidity(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint8 mode
    )
        internal
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        // (1) compute target, issue principal & yields & add liquidity to space
        (issued, lpShares) = _computeIssueAddLiq(adapter, maturity, tBal);

        if (issued > 0) {
            // issue = 0 means that we are on the first pool provision or that the principal:target ratio is 0:target
            if (mode == 0) {
                // (2) Sell yields
                tAmount = _swapYieldForTarget(address(this), adapter, maturity, issued);
                // (3) Send remaining Target back to the User
                ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tAmount);
            } else {
                // (4) Send Yield back to the User
                ERC20(divider.yield(adapter, maturity)).safeTransfer(msg.sender, issued);
            }
        }
    }

    /// @dev Calculates amount of principal in target terms (see description on `_computeTarget`) then issues
    /// Principal and Yield Tokens with the calculated amount and finally adds liquidity to space with the principal issued
    /// and the diff between the target initially passed and the calculated amount
    function _computeIssueAddLiq(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) internal returns (uint256, uint256) {
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        // Compute target
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
        (uint256 principali, uint256 targeti) = pool.getIndices(); // Ensure we have the right token Indices

        // We do not add Principal liquidity if it haven't been initialized yet
        bool principalInitialized = balances[principali] != 0;
        uint256 zBalInTarget = principalInitialized
            ? _computeTarget(adapter, balances[principali], balances[targeti], tBal)
            : 0;

        // Issue Principal & Yield (skip if first pool provision)
        uint256 issued = zBalInTarget > 0 ? divider.issue(adapter, maturity, zBalInTarget) : 0;

        // Add liquidity to Space & send the LP Shares to recipient
        uint256[] memory amounts = new uint256[](2);
        amounts[targeti] = tBal - zBalInTarget;
        amounts[principali] = issued;
        uint256 lpShares = _addLiquidityToSpace(pool, PoolLiquidity(tokens, amounts));
        return (issued, lpShares);
    }

    /// @dev Based on principal:target ratio from current pool reserves and tBal passed
    /// calculates amount of tBal needed so as to issue Principal that would keep the ratio
    function _computeTarget(
        address adapter,
        uint256 principaliBal,
        uint256 targetiBal,
        uint256 tBal
    ) internal returns (uint256) {
        uint256 tBase = 10**ERC20(Adapter(adapter).target()).decimals();
        uint256 ifee = Adapter(adapter).ifee();
        return
            tBal.fmul(
                principaliBal.fdiv(
                    Adapter(adapter).scale().fmul(FixedMath.WAD - ifee).fmul(targetiBal) + principaliBal,
                    tBase
                ),
                tBase
            );
    }

    function _removeLiquidity(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) internal returns (uint256 tBal, uint256 zBal) {
        address target = Adapter(adapter).target();
        address principal = divider.principal(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        bytes32 poolId = pool.getPoolId();

        // (0) Pull LP tokens from sender
        ERC20(address(pool)).safeTransferFrom(msg.sender, address(this), lpBal);

        // (1) Remove liquidity from Space
        uint256 _zBal;
        (tBal, _zBal) = _removeLiquidityFromSpace(poolId, principal, target, minAmountsOut, lpBal);

        if (divider.mscale(adapter, maturity) > 0) {
            if (uint256(Adapter(adapter).level()).redeemPrincipalRestricted()) {
                ERC20(principal).safeTransfer(msg.sender, _zBal);
                zBal = _zBal;
            } else {
                // (2) Redeem Principal for Target
                tBal += divider.redeemPrincipal(adapter, maturity, _zBal);
            }
        } else {
            // (2) Sell Principal for Target
            tBal += _swap(principal, target, _zBal, poolId, minAccepted);
        }
    }

    /// @notice Initiates a flash loan of Target, swaps target amount to principal and combines
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param cBalIn Yield amount the user has sent in
    /// @param amount target amount to borrow
    /// @return amount of Target obtained from a sale of Yield
    function _flashBorrowAndSwap(
        bytes memory data,
        address adapter,
        uint256 maturity,
        uint256 cBalIn,
        uint256 amount
    ) internal returns (uint256) {
        ERC20 target = ERC20(Adapter(adapter).target());
        uint256 _allowance = target.allowance(address(this), address(adapter));
        if (_allowance < amount) target.approve(address(adapter), type(uint256).max);
        (bool result, uint256 value) = Adapter(adapter).flashLoan(
            data,
            address(this),
            adapter,
            maturity,
            cBalIn,
            amount
        );
        if (!result) revert Errors.FlashBorrowFailed();
        return value;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        bytes calldata,
        address initiator,
        address adapter,
        uint256 maturity,
        uint256 cBalIn,
        uint256 amount
    ) external returns (bytes32, uint256) {
        if (msg.sender != address(adapter)) revert Errors.FlashUntrustedBorrower();
        if (initiator != address(this)) revert Errors.FlashUntrustedLoanInitiator();
        address yield = divider.yield(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // Because Space utilizes power ofs liberally in its invariant, there is some error
        // in the amountIn we estimated that we'd need in `_swapYieldForTarget` to get a `zBal` out
        // that matched our Yield balance. Tokens with more than 18 decimals are not supported.
        uint256 acceptableError = ERC20(yield).decimals() < 9 ? 1 : 1e10 / 10**(18 - ERC20(yield).decimals());

        // Swap Target for Principal
        uint256 zBal = _swap(
            Adapter(adapter).target(),
            divider.principal(adapter, maturity),
            amount,
            pool.getPoolId(),
            cBalIn - acceptableError
        );

        // We take the lowest of the two balances, as long as they're within a margin of acceptable error.
        if (zBal >= cBalIn + acceptableError && zBal <= cBalIn - acceptableError) revert Errors.UnexpectedSwapAmount();

        // Combine principal and yield
        uint256 tBal = divider.combine(adapter, maturity, zBal < cBalIn ? zBal : cBalIn);

        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
    }

    function _addLiquidityToSpace(BalancerPool pool, PoolLiquidity memory liq) internal returns (uint256) {
        bytes32 poolId = pool.getPoolId();
        IAsset[] memory assets = _convertERC20sToAssets(liq.tokens);
        for (uint8 i; i < liq.tokens.length; i++) {
            // Tokens and amounts must be in same order
            liq.tokens[i].approve(address(balancerVault), liq.amounts[i]);
        }

        // Behaves like EXACT_TOKENS_IN_FOR_BPT_OUT, user sends precise quantities of tokens,
        // and receives an estimated but unknown (computed at run time) quantity of BPT
        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: liq.amounts,
            userData: abi.encode(liq.amounts),
            fromInternalBalance: false
        });
        balancerVault.joinPool(poolId, address(this), msg.sender, request);
        return ERC20(address(pool)).balanceOf(msg.sender);
    }

    function _removeLiquidityFromSpace(
        bytes32 poolId,
        address principal,
        address target,
        uint256[] memory minAmountsOut,
        uint256 lpBal
    ) internal returns (uint256, uint256) {
        // ExitPoolRequest params
        (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory assets = _convertERC20sToAssets(tokens);
        BalancerVault.ExitPoolRequest memory request = BalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(lpBal),
            toInternalBalance: false
        });
        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);

        return (ERC20(target).balanceOf(address(this)), ERC20(principal).balanceOf(address(this)));
    }

    /// @notice From: https://github.com/balancer-labs/balancer-examples/blob/master/packages/liquidity-provision/contracts/LiquidityProvider.sol#L33
    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }

    /* ========== LOGS ========== */

    event FactoryChanged(address indexed adapter, bool indexed isOn);
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
}
