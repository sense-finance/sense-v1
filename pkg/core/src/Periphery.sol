// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { FixedMath } from "./external/FixedMath.sol";
import { BalancerVault, IAsset } from "./external/balancer/Vault.sol";
import { BalancerPool } from "./external/balancer/Pool.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";
import { BaseFactory as Factory } from "./adapters/BaseFactory.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Token } from "./tokens/Token.sol";

interface SpaceFactoryLike {
    function create(address, uint256) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);
}

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;
    using Errors for string;

    /// @notice Program state
    Divider public immutable divider;
    PoolManager public immutable poolManager;
    SpaceFactoryLike public immutable spaceFactory;
    BalancerVault public immutable balancerVault;

    mapping(address => bool) public factories; // adapter factories -> is supported
    mapping(address => address) public factory; // adapter -> factory

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

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Sponsor a new Series
    /// @dev Calls divider to initalise a new series
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    function sponsorSeries(address adapter, uint256 maturity) external returns (address zero, address claim) {
        (, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();

        // Transfer stakeSize from sponsor into this contract
        ERC20(stake).safeTransferFrom(msg.sender, address(this), stakeSize);

        // Approve divider to withdraw stake assets
        ERC20(stake).safeApprove(address(divider), stakeSize);

        (zero, claim) = divider.initSeries(adapter, maturity, msg.sender);

        // If it is a Sense verified adapter
        if (factory[adapter] != address(0)) {
            address pool = spaceFactory.create(adapter, maturity);
            poolManager.queueSeries(adapter, maturity, pool);
        }
        emit SeriesSponsored(adapter, maturity, msg.sender);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Adapter via the AdapterFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address
    /// @param target Target to onboard
    function onboardAdapter(address f, address target) external returns (address adapterClone) {
        require(factories[f], Errors.FactoryNotSupported);
        adapterClone = Factory(f).deployAdapter(target);
        // Ping scale to ensure an lscale is cached
        Adapter(adapterClone).scale();
        ERC20(target).safeApprove(address(divider), type(uint256).max);
        ERC20(target).safeApprove(address(adapterClone), type(uint256).max);
        poolManager.addTarget(target, adapterClone);
        factory[adapterClone] = f;
        emit AdapterOnboarded(adapterClone);
    }

    /// @notice Swap Target to Zeros of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    /// @param minAccepted Min accepted amount of Zeros
    /// @return amount of Zeros received
    function swapTargetForZeros(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal); // pull target
        return _swapTargetForZeros(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Underlying to Zeros of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    /// @param minAccepted Min accepted amount of Zeros
    /// @return amount of Zeros received
    function swapUnderlyingForZeros(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20 underlying = ERC20(Adapter(adapter).underlying());
        underlying.safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        underlying.safeApprove(adapter, uBal); // approve adapter to pull uBal
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        return _swapTargetForZeros(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Target to Claims of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    function swapTargetForClaims(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
        return _swapTargetForClaims(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Underlying to Claims of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    function swapUnderlyingForClaims(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20 underlying = ERC20(Adapter(adapter).underlying());
        underlying.safeTransferFrom(msg.sender, address(this), uBal); // pull target
        underlying.safeApprove(adapter, uBal); // approve adapter to pull underlying
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        return _swapTargetForClaims(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Zeros for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Zeros to sell
    /// @param minAccepted Min accepted amount of Target
    function swapZerosForTarget(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _swapZerosForTarget(adapter, maturity, zBal, minAccepted); // swap zeros for target
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal); // transfer target to msg.sender
        return tBal;
    }

    /// @notice Swap Zeros for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Zeros to sell
    /// @param minAccepted Min accepted amount of Target
    function swapZerosForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _swapZerosForTarget(adapter, maturity, zBal, minAccepted); // swap zeros for target
        ERC20(Adapter(adapter).target()).safeApprove(adapter, tBal); // approve adapter to pull target
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal); // unwrap target into underlying
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal); // transfer underlying to msg.sender
        return uBal;
    }

    /// @notice Swap Claims for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Claims to swap
    function swapClaimsForTarget(
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) external returns (uint256) {
        uint256 tBal = _swapClaimsForTarget(msg.sender, adapter, maturity, cBal);
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    /// @notice Swap Claims for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Claims to swap
    function swapClaimsForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) external returns (uint256) {
        uint256 tBal = _swapClaimsForTarget(msg.sender, adapter, maturity, cBal);
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal);
        return uBal;
    }

    /// @notice Adds liquidity providing target
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to provide
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
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
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
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
        underlying.safeApprove(adapter, uBal);
        // Wrap Underlying into Target
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);
        return _addLiquidity(adapter, maturity, tBal, mode);
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns target
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    function removeLiquidityToTarget(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal); // Send Target back to the User
        return tBal;
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns underlying
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    function removeLiquidityToUnderlying(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).target()).safeApprove(adapter, tBal);
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal); // Send Underlying back to the User
        return uBal;
    }

    /// @notice Migrates liquidity position from one series to another
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param srcAdapter Adapter address for the source Series
    /// @param dstAdapter Adapter address for the destination Series
    /// @param srcMaturity Maturity date for the source Series
    /// @param dstMaturity Maturity date for the destination Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
    /// @return see return description of _addLiquidity
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
            uint256,
            uint256,
            uint256
        )
    {
        require(Adapter(srcAdapter).target() == Adapter(dstAdapter).target(), Errors.TargetMismatch);
        uint256 tBal = _removeLiquidity(srcAdapter, srcMaturity, lpBal, minAmountsOut, minAccepted);
        return _addLiquidity(dstAdapter, dstMaturity, tBal, mode);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Enable or disable a factory
    /// @param f Factory's address
    /// @param isOn Flag setting this factory to enabled or disabled
    function setFactory(address f, bool isOn) external requiresTrust {
        require(factories[f] != isOn, Errors.ExistingValue);
        factories[f] = isOn;
        emit FactoryChanged(f, isOn);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 poolId,
        uint256 minAccepted
    ) internal returns (uint256 amountOut) {
        // approve vault to spend tokenIn
        ERC20(assetIn).safeApprove(address(balancerVault), amountIn);

        BalancerVault.SingleSwap memory request = BalancerVault.SingleSwap({
            poolId: poolId,
            kind: BalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amountIn,
            userData: "0x" // TODO: are we sure about this?
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

    function _swapZerosForTarget(
        address adapter,
        uint256 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal); // pull zeros
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        return _swap(zero, Adapter(adapter).target(), zBal, pool.getPoolId(), minAccepted); // swap zeros for underlying
    }

    function _swapTargetForZeros(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        uint256 zBal = _swap(Adapter(adapter).target(), zero, tBal, pool.getPoolId(), minAccepted); // swap target for zeros
        ERC20(zero).safeTransfer(msg.sender, zBal); // transfer bought zeros to user
        return zBal;
    }

    function _swapTargetForClaims(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // issue zeros and claims & swap zeros for target
        uint256 issued = divider.issue(adapter, maturity, tBal);
        tBal = _swap(zero, Adapter(adapter).target(), issued, pool.getPoolId(), minAccepted);

        // transfer claims & target to user
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        ERC20(claim).safeTransfer(msg.sender, issued);
        return issued;
    }

    function _swapClaimsForTarget(
        address sender,
        address adapter,
        uint256 maturity,
        uint256 cBal
    ) internal returns (uint256) {
        (, address claim, , , , , , , ) = divider.series(adapter, maturity);

        // Because there's some margin of error in the pricing functions here, smaller
        // swaps will be unreliable.
        require(cBal * 10**(18 - ERC20(claim).decimals()) > 1e12, Errors.SwapTooSmall);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // Transfer claims into this contract if needed
        if (sender != address(this)) ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // Calculate target to borrow by calling AMM
        bytes32 poolId = pool.getPoolId();
        (uint8 zeroi, uint256 targeti) = pool.getIndices();
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolId);
        // Determine how much Target we'll need in to get `cBal` balance of Target out
        // (space doesn't directly use of the fields from `SwapRequest` beyond `poolId`, so the values after are placeholders)
        uint256 targetToBorrow = BalancerPool(pool).onSwap(
            BalancerPool.SwapRequest({
                kind: BalancerVault.SwapKind.GIVEN_OUT,
                tokenIn: tokens[targeti],
                tokenOut: tokens[zeroi],
                amount: cBal,
                poolId: poolId,
                lastChangeBlock: 0,
                from: address(0),
                to: address(0),
                userData: ""
            }),
            balances[targeti],
            balances[zeroi]
        );

        // Flash borrow target (following actions in `onFlashLoan`)
        return _flashBorrow("0x", adapter, maturity, cBal, targetToBorrow);
    }

    /// @return tAmount if mode = 0, target received from selling Claims, otherwise, returns 0  
    /// @return issued returns amount of Claims issued (and received) except first provision which returns 0  
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
        (, address claim, , , , , , , ) = divider.series(adapter, maturity);

        // (1) compute target, issue zeros & claims & add liquidity to space
        (issued, lpShares) = _computeIssueAddLiq(adapter, maturity, tBal);

        if (issued > 0) {
            // issue = 0 means that we are on the first pool provision or that the zero:target ratio is 0:target
            if (mode == 0) {
                // (2) Sell claims
                tAmount = _swapClaimsForTarget(address(this), adapter, maturity, issued);
                // (3) Send remaining Target back to the User
                ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tAmount);
            } else {
                // (4) Send Claims back to the User
                ERC20(claim).safeTransfer(msg.sender, issued);
            }
        }
    }

    /// @dev Calculates amount of zeros in target terms (see description on `_computeTarget`) then issues
    /// Zeros and Claims with the calculated amount and finally adds liquidity to space with the zeros issued
    /// and the diff between the target initially passed and the calculated amount
    function _computeIssueAddLiq(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) internal returns (uint256, uint256) {
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        bool isFirstProvision = pool.totalSupply() == 0;

        // Compute target
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
        (uint8 zeroi, uint8 targeti) = pool.getIndices(); // Ensure we have the right token Indices

        // We do not add zeros liquidity on the first provision (hence, we skip computation)
        uint256 zBalInTarget = isFirstProvision ? 0 : _computeTarget(adapter, balances[zeroi], balances[targeti], tBal);

        // Issue Zeros & Claim (skip if first pool provision)
        uint256 issued = zBalInTarget > 0 ? divider.issue(adapter, maturity, zBalInTarget) : 0;

        // Add liquidity to Space & send the LP Shares to recipient
        uint256[] memory amounts = new uint256[](2);
        amounts[targeti] = tBal - zBalInTarget;
        amounts[zeroi] = issued;
        uint256 lpShares = _addLiquidityToSpace(pool, PoolLiquidity(tokens, amounts));
        return (issued, lpShares);
    }

    /// @dev Based on zeros:target ratio from current pool reserves and tBal passed
    /// calculates amount of tBal needed so as to issue Zeros that would keep the ratio
    function _computeTarget(
        address adapter,
        uint256 zeroiBal,
        uint256 targetiBal,
        uint256 tBal
    ) internal returns (uint256) {
        uint256 tBase = 10**ERC20(Adapter(adapter).target()).decimals();
        return
            tBal.fmul(zeroiBal.fdiv(Adapter(adapter).scale().fmul(targetiBal, tBase) + zeroiBal, FixedMath.WAD), tBase); // ABDK formula
    }

    function _removeLiquidity(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) internal returns (uint256) {
        address target = Adapter(adapter).target();
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        bytes32 poolId = pool.getPoolId();

        // (0) Pull LP tokens from sender
        ERC20(address(pool)).safeTransferFrom(msg.sender, address(this), lpBal);

        // (1) Remove liquidity from Space
        (uint256 tBal, uint256 zBal) = _removeLiquidityFromSpace(poolId, zero, target, minAmountsOut, lpBal);

        if (block.timestamp >= maturity) {
            // (2) Redeem Zeros for Target
            tBal += divider.redeemZero(adapter, maturity, zBal);
        } else {
            // (2) Sell Zeros for Target
            tBal += _swap(zero, target, zBal, poolId, minAccepted);
        }

        return tBal;
    }

    /// @notice Initiate a flash loan
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param cBalIn Claim amount the user has sent in
    /// @param amount target amount to borrow
    /// @return amount of Target obtained from a sale of Claims
    function _flashBorrow(
        bytes memory data,
        address adapter,
        uint256 maturity,
        uint256 cBalIn,
        uint256 amount
    ) internal returns (uint256) {
        ERC20 target = ERC20(Adapter(adapter).target());
        uint256 _allowance = target.allowance(address(this), address(adapter));
        if (_allowance < amount) target.safeApprove(address(adapter), type(uint256).max);
        (bool result, uint256 value) = Adapter(adapter).flashLoan(
            data,
            address(this),
            adapter,
            maturity,
            cBalIn,
            amount
        );
        require(result);
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
        require(msg.sender == address(adapter), Errors.FlashUntrustedBorrower);
        require(initiator == address(this), Errors.FlashUntrustedLoanInitiator);
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        // Because Space utilizes power ofs liberally in its invariant, there is some error
        // in the amountIn we estimated that we'd need in `_swapClaimsForTarget` to get a `zBal` out
        // that matched our Claim balance.
        uint256 acceptableError = ERC20(claim).decimals() < 9 ? 1 : 1e10 / 10**(18 - ERC20(claim).decimals());

        // Swap Target for Zeros
        uint256 zBal = _swap(Adapter(adapter).target(), zero, amount, pool.getPoolId(), cBalIn - acceptableError);

        // We take the lowest of the two balances, as long as they're within a margin of acceptable error.
        require(zBal < cBalIn + acceptableError && zBal > cBalIn - acceptableError, Errors.UnexpectedSwapAmount);

        // Combine zeros and claim
        uint256 tBal = divider.combine(adapter, maturity, zBal < cBalIn ? zBal : cBalIn);

        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
    }

    function _addLiquidityToSpace(BalancerPool pool, PoolLiquidity memory liq) internal returns (uint256) {
        bytes32 poolId = pool.getPoolId();
        IAsset[] memory assets = _convertERC20sToAssets(liq.tokens);
        for (uint8 i; i < liq.tokens.length; i++) {
            // tokens and amounts must be in same order
            liq.tokens[i].safeApprove(address(balancerVault), liq.amounts[i]);
        }
        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: liq.amounts,
            userData: abi.encode(liq.amounts), // behaves like EXACT_TOKENS_IN_FOR_BPT_OUT, user sends precise quantities of tokens, and receives an estimated but unknown (computed at run time) quantity of BPT. (more info here https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-joins.md)
            fromInternalBalance: false
        });
        uint256 lpSharesBefore = ERC20(address(pool)).balanceOf(msg.sender);
        balancerVault.joinPool(poolId, address(this), msg.sender, request);
        return ERC20(address(pool)).balanceOf(msg.sender) - lpSharesBefore;
    }

    function _removeLiquidityFromSpace(
        bytes32 poolId,
        address zero,
        address target,
        uint256[] memory minAmountsOut,
        uint256 lpBal
    ) internal returns (uint256, uint256) {
        uint256 tBalBefore = ERC20(target).balanceOf(address(this));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(this));

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

        uint256 zBalAfter = ERC20(zero).balanceOf(address(this));
        uint256 tBalAfter = ERC20(target).balanceOf(address(this));
        return (tBalAfter - tBalBefore, zBalAfter - zBalBefore);
    }

    // @author https://github.com/balancer-labs/balancer-examples/blob/master/packages/liquidity-provision/contracts/LiquidityProvider.sol#L33
    // @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }

    /* ========== LOGS ========== */

    event FactoryChanged(address indexed adapter, bool indexed isOn);
    event SeriesSponsored(address indexed adapter, uint256 indexed maturity, address indexed sponsor);
    event AdapterOnboarded(address adapter);
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
