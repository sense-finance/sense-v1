// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";
import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";

import { IMinimalSwapInfoPool } from "@balancer-labs/v2-vault/contracts/interfaces/IMinimalSwapInfoPool.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { IERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import { Errors, _require } from "./Errors.sol";

interface AdapterLike {
    function scale() external returns (uint256);

    function target() external returns (address);

    function symbol() external returns (string memory);

    function name() external returns (string memory);
}

/*
                    SPACE
        *   '*
                *
                        *
                            *
                    *
                            *
                .                      .
                .                      ;
                :                  - --+- -
                !           .          !

*/

/// @notice A Yieldspace implementation extended such that LPs can deposit
/// [Zero, Yield-bearing asset], rather than [Zero, Underlying], while keeping the benefits of the
/// yieldspace invariant (e.g. it can hold [Zero, cDAI], rather than [Zero, DAI], while still operating
/// in "yield space" for the zero-coupon side. See the YieldSpace paper for more https://yield.is/YieldSpace.pdf)
/// @dev We use much more internal storage here than in other Sense contracts because it
/// conforms to Balancer's own style, and we're using several Balancer functions that play nicer if we do.
/// @dev Requires an external "Adapter" contract with a `scale()` function which returns the
/// current exchange rate from Target to the Underlying asset.
contract Space is IMinimalSwapInfoPool, BalancerPoolToken {
    using FixedPoint for uint256;

    /* ========== CONSTANTS ========== */

    /// @notice Minimum BPT we can have for this pool after initialization
    uint256 public constant MINIMUM_BPT = 1e6;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Adapter address for the associated Series
    address public immutable adapter;

    /// @notice Maturity timestamp for associated Series
    uint256 public immutable maturity;

    /// @notice Zero token index (there are only two tokens in this pool, so `targeti` is always just the complement)
    uint8 public immutable zeroi;

    /// @notice Yieldspace config, passed in from the Space Factory
    uint256 public immutable ts;
    uint256 public immutable g1;
    uint256 public immutable g2;

    /* ========== INTERNAL IMMUTABLES ========== */

    /// @dev Balancer pool id (as registered with the Balancer Vault)
    bytes32 internal immutable _poolId;

    /// @dev Token registered at index zero for this pool
    IERC20 internal immutable _token0;

    /// @dev Token registered at index one for this pool
    IERC20 internal immutable _token1;

    /// @dev Factor needed to scale the Zero token to 18 decimals
    uint256 internal immutable _scalingFactorZero;

    /// @dev Factor needed to scale the Target token to 18 decimals
    uint256 internal immutable _scalingFactorTarget;

    /// @dev Balancer Vault
    IVault internal immutable _vault;

    /// @dev Contract that collects Balancer protocol fees
    address internal immutable _protocolFeesCollector;

    /* ========== INTERNAL MUTABLE STORAGE ========== */

    /// @dev Scale value for the yield-bearing asset's first `join` (i.e. initialization)
    uint256 internal _initScale;

    /// @dev Invariant tracking for calculating Balancer protocol fees
    uint256 internal _lastToken0Reserve;
    uint256 internal _lastToken1Reserve;

    constructor(
        IVault vault,
        address _adapter,
        uint256 _maturity,
        address zero,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) BalancerPoolToken(AdapterLike(_adapter).name(), AdapterLike(_adapter).symbol()) {
        bytes32 poolId = vault.registerPool(IVault.PoolSpecialization.TWO_TOKEN);

        address target = AdapterLike(_adapter).target();
        IERC20[] memory tokens = new IERC20[](2);

        // Ensure that the array of tokens is correctly ordered
        uint8 _zeroi = zero < target ? 0 : 1;
        tokens[_zeroi] = IERC20(zero);
        tokens[1 - _zeroi] = IERC20(target);
        vault.registerTokens(poolId, tokens, new address[](2));

        // Set Balancer-specific pool config
        _vault = vault;
        _poolId = poolId;
        _token0 = tokens[0];
        _token1 = tokens[1];
        _protocolFeesCollector = address(vault.getProtocolFeesCollector());

        _scalingFactorZero = 10**(18 - ERC20(zero).decimals());
        _scalingFactorTarget = 10**(18 - ERC20(target).decimals());

        // Set Yieldspace config
        g1 = _g1; // fees are baked into factors `g1` & `g2`,
        g2 = _g2; // see the "Fees" section of the yieldspace paper
        ts = _ts;

        // Set Space-specific slots
        zeroi = _zeroi;
        adapter = _adapter;
        maturity = _maturity;
    }

    /* ========== BALANCER VAULT HOOKS ========== */

    function onJoinPool(
        bytes32 poolId,
        address, /* _sender */
        address recipient,
        uint256[] memory reserves,
        uint256, /* _lastChangeBlock */
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external override onlyVault(poolId) returns (uint256[] memory, uint256[] memory) {
        // Space does not have multiple join types like other Balancer pools,
        // instead, its `joinPool` always behaves like `EXACT_TOKENS_IN_FOR_BPT_OUT`

        _require(maturity >= block.timestamp, Errors.POOL_PAST_MATURITY);

        uint256[] memory reqAmountsIn = abi.decode(userData, (uint256[]));

        // Upscale both requested amounts and reserves to 18 decimals
        _upscaleArray(reserves);
        _upscaleArray(reqAmountsIn);

        if (totalSupply() == 0) {
            (uint8 _zeroi, uint8 _targeti) = getIndices();
            uint256 initScale = AdapterLike(adapter).scale();

            // Convert target balance into Underlying
            // note: We assume scale values will always be 18 decimals
            uint256 underlyingIn = reqAmountsIn[_targeti].mulDown(initScale);

            // Just like weighted pool 2 token from the balancer v2 monorepo,
            // we lock MINIMUM_BPT in by minting it for the zero address. This reduces potential
            // issues with rounding and ensures that this code path will only be executed once
            _mintPoolTokens(address(0), MINIMUM_BPT);

            // Mint the recipient BPT comensurate with the value of their join in Underlying
            _mintPoolTokens(recipient, underlyingIn - MINIMUM_BPT);

            // Amounts entering the Pool, so we round up
            _downscaleUpArray(reqAmountsIn);

            // Set the scale value all future deposits will be backdated to
            _initScale = initScale;

            // For the first join, we don't pull any Zeros, regardless of what the caller requested.
            // This starts this pool off as synthetic Underlying only, as the yieldspace invariant expects
            delete reqAmountsIn[_zeroi];

            // Cache new reserves, post join
            _cacheReserves(reserves);

            return (reqAmountsIn, new uint256[](2));
        } else {
            // Calculate fees due before updating bpt balances to determine invariant growth from just swap fees
            if (protocolSwapFeePercentage != 0) {
                _mintPoolTokens(_protocolFeesCollector, _bptFeeDue(reserves, protocolSwapFeePercentage));
            }

            (uint256 bptToMint, uint256[] memory amountsIn) = _tokensInForBptOut(reqAmountsIn, reserves);

            // Amounts entering the Pool, so we round up
            _downscaleUpArray(amountsIn);

            // `recipient` receives liquidity tokens
            _mintPoolTokens(recipient, bptToMint);

            // Update reserves for caching
            reserves[0] += amountsIn[0];
            reserves[1] += amountsIn[1];

            // Cache new reserves, post join
            _cacheReserves(reserves);

            // Inspired by PR #990 in the balancer v2 monorepo, we always return zero dueProtocolFeeAmounts
            // to the Vault, and pay protocol fees by minting BPT directly to the protocolFeeCollector instead
            return (amountsIn, new uint256[](2));
        }
    }

    function onExitPool(
        bytes32 poolId,
        address sender,
        address, /* _recipient */
        uint256[] memory reserves,
        uint256, /* _lastChangeBlock */
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external override onlyVault(poolId) returns (uint256[] memory, uint256[] memory) {
        // Space does not have multiple exit types like other Balancer pools,
        // instead, its `exitPool` always behaves like `EXACT_BPT_IN_FOR_TOKENS_OUT`

        // Upscale reserves to 18 decimals
        _upscaleArray(reserves);

        // Calculate fees due before updating bpt balances to determine invariant growth from just swap fees
        if (protocolSwapFeePercentage != 0) {
            // Balancer fealty
            _mintPoolTokens(_protocolFeesCollector, _bptFeeDue(reserves, protocolSwapFeePercentage));
        }

        // Determine what percentage of the pool the BPT being passed in is
        uint256 bptAmountIn = abi.decode(userData, (uint256));
        uint256 pctPool = bptAmountIn.divDown(totalSupply());

        // Calculate the amount of tokens owed in return for giving that amount of BPT in
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[0] = reserves[0].mulDown(pctPool);
        amountsOut[1] = reserves[1].mulDown(pctPool);

        // Amounts are leaving the Pool, so we round down
        _downscaleDownArray(amountsOut);

        // `sender` pays for the liquidity
        _burnPoolTokens(sender, bptAmountIn);

        // TODO gas efficiency
        // Update reserves for caching
        reserves[0] -= amountsOut[0];
        reserves[1] -= amountsOut[1];

        // Cache new invariant and reserves, post exit
        _cacheReserves(reserves);

        return (amountsOut, new uint256[](2));
    }

    function onSwap(
        SwapRequest memory request,
        uint256 reservesTokenIn,
        uint256 reservesTokenOut
    ) external override returns (uint256) {
        bool token0In = request.tokenIn == _token0;
        bool zeroIn = token0In ? zeroi == 0 : zeroi == 1;

        uint256 scalingFactorTokenIn = _scalingFactor(zeroIn);
        uint256 scalingFactorTokenOut = _scalingFactor(!zeroIn);

        // Upscale reserves to 18 decimals
        reservesTokenIn = _upscale(reservesTokenIn, scalingFactorTokenIn);
        reservesTokenOut = _upscale(reservesTokenOut, scalingFactorTokenOut);

        uint256 scale = AdapterLike(adapter).scale();

        if (zeroIn) {
            // Add LP supply to Zero reserves, as suggested by the yieldspace paper
            reservesTokenIn += totalSupply();

            // Backdate the Target reserves and convert to Underlying, as if it were still t0 (initialization)
            reservesTokenOut = reservesTokenOut.mulDown(_initScale);
        } else {
            // Backdate the Target reserves and convert to Underlying, as if it were still t0 (initialization)
            reservesTokenIn = reservesTokenIn.mulDown(_initScale);

            // Add LP supply to Zero reserves, as suggested by the yieldspace paper
            reservesTokenOut += totalSupply();
        }

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            request.amount = _upscale(request.amount, scalingFactorTokenIn);
            // If Target is being swapped in, convert the amountIn to Underlying using present day Scale
            if (!zeroIn) {
                request.amount = request.amount.mulDown(scale);
            }

            // Determine the amountOut
            uint256 amountOut = _onSwap(zeroIn, true, request.amount, reservesTokenIn, reservesTokenOut);
            // If Zeros are being swapped in, convert the Underlying out back to Target using present day Scale
            if (zeroIn) {
                amountOut = amountOut.divDown(scale);
            }

            // AmountOut, so we round down
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            request.amount = _upscale(request.amount, scalingFactorTokenOut);
            // If Zeros are being swapped in, convert the amountOut from Target to Underlying using present day Scale
            if (zeroIn) {
                request.amount = request.amount.mulDown(scale);
            }

            // Determine the amountIn
            uint256 amountIn = _onSwap(zeroIn, false, request.amount, reservesTokenIn, reservesTokenOut);
            // If Target is being swapped in, convert the amountIn back to Target using present day Scale
            if (!zeroIn) {
                amountIn = amountIn.divDown(scale);
            }

            // amountIn, so we round up
            return _downscaleUp(amountIn, scalingFactorTokenIn);
        }
    }

    /* ========== INTERNAL JOIN/SWAP ACCOUNTING ========== */

    /// @notice Calculate the max amount of BPT that can be minted from the requested amounts in,
    // given the ratio of the reserves, and assuming we don't make any swaps
    function _tokensInForBptOut(uint256[] memory reqAmountsIn, uint256[] memory reserves)
        internal
        view
        returns (uint256, uint256[] memory)
    {
        // Disambiguate reserves wrt token type
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        (uint256 zeroReserves, uint256 targetReserves) = (reserves[_zeroi], reserves[_targeti]);

        uint256[] memory amountsIn = new uint256[](2);

        // If the pool has been initialized, but there aren't yet any Zeros in it
        if (zeroReserves == 0) {
            uint256 reqTargetIn = reqAmountsIn[_targeti];
            // Mint LP shares according to the relative amount of Target being offered
            uint256 bptToMint = (totalSupply() * reqTargetIn) / targetReserves;

            // Pull the entire offered Target
            amountsIn[_targeti] = reqTargetIn;

            return (bptToMint, amountsIn);
        } else {
            // Disambiguate requested amounts wrt token type
            (uint256 reqZerosIn, uint256 reqTargetIn) = (reqAmountsIn[_zeroi], reqAmountsIn[_targeti]);
            // Caclulate the percentage of the pool we'd get if we pulled all of the requested Target in
            uint256 bptToMintTarget = (totalSupply() * reqTargetIn) / targetReserves;

            // Caclulate the percentage of the pool we'd get if we pulled all of the requested Zeros in
            uint256 bptToMintZeros = (totalSupply() * reqZerosIn) / zeroReserves;

            // Determine which amountIn is our limiting factor
            if (bptToMintTarget < bptToMintZeros) {
                amountsIn[_zeroi] = (zeroReserves * reqTargetIn) / targetReserves;
                amountsIn[_targeti] = reqTargetIn;

                return (bptToMintTarget, amountsIn);
            } else {
                amountsIn[_zeroi] = reqZerosIn;
                amountsIn[_targeti] = (targetReserves * reqZerosIn) / zeroReserves;

                return (bptToMintZeros, amountsIn);
            }
        }
    }

    /// @notice Calculate the missing variable in the yield space equation given the direction (Zero in vs. out)
    /// @dev We round in favor of the LPs, meaning that traders get slightly worse prices than they would if we had full
    /// precision. However, the differences are small (on the order of 1e-11), and should only matter for very small trades.
    function _onSwap(
        bool zeroIn,
        bool givenIn,
        uint256 amountDelta,
        uint256 reservesTokenIn,
        uint256 reservesTokenOut
    ) internal view returns (uint256) {
        // xPre = token in reserves pre swap
        // yPre = token out reserves pre swap

        // Seconds until maturity, in 18 decimals
        // After maturity, this pool becomes a constant sum AMM
        uint256 ttm = maturity > block.timestamp ? uint256(maturity - block.timestamp) * FixedPoint.ONE : 0;

        // Time shifted partial `t` from the yieldspace paper (`ttm` adjusted by some factor `ts`)
        uint256 t = ts.mulDown(ttm);

        // Full `t` with fees baked in
        uint256 a = (zeroIn ? g2 : g1).mulUp(t).complement();

        // Pow up for `x1` & `y1` and down for `xOrY2` causes the pow induced error for `xOrYPost`
        // to tend towards higher values rather than lower.
        // Effectively we're adding a little bump up for ammountIn, and down for amountOut

        // x1 = xPre ^ a; y1 = yPre ^ a
        uint256 x1 = reservesTokenIn.powUp(a);
        uint256 y1 = reservesTokenOut.powUp(a);

        // y2 = (yPre - amountOut) ^ a; x2 = (xPre + amountIn) ^ a
        uint256 xOrY2 = (givenIn ? reservesTokenIn + amountDelta : reservesTokenOut - amountDelta).powDown(a);

        // x1 + y1 = xOrY2 + xOrYPost ^ a
        // -> xOrYPost ^ a = x1 + y1 - x2
        // -> xOrYPost = (x1 + y1 - xOrY2) ^ (1 / a)
        uint256 xOrYPost = (x1 + y1 - xOrY2).powUp(FixedPoint.ONE.divDown(a));
        _require(!givenIn || reservesTokenOut > xOrYPost, Errors.SWAP_TOO_SMALL);

        // amountOut = yPre - yPost; amountIn = xPost - xPre
        return givenIn ? reservesTokenOut.sub(xOrYPost) : xOrYPost.sub(reservesTokenIn);
    }

    /* ========== PROTOCOL FEE HELPERS ========== */

    /// @notice Determine the growth in the invariant due to swap fees only
    /// @dev This can't be a view function b/c `Adapter.scale` is not a view function
    function _bptFeeDue(uint256[] memory reserves, uint256 protocolSwapFeePercentage) internal view returns (uint256) {
        uint256 ttm = maturity > block.timestamp ? uint256(maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        // Invariant growth from time only
        uint256 timeOnlyInvariant = _lastToken0Reserve.powDown(a) + _lastToken1Reserve.powDown(a);
        (uint8 _zeroi, uint8 _targeti) = getIndices();

        // `x` & `y` for the actual invariant, with growth from time and fees
        uint256 x = (reserves[_zeroi] + totalSupply()).powDown(a);
        uint256 y = reserves[_targeti].mulDown(_initScale).powDown(a);

        return
            (x + y).divDown(timeOnlyInvariant).sub(FixedPoint.ONE).mulDown(totalSupply()).mulDown(
                protocolSwapFeePercentage
            );
    }

    /// @notice Cache the given reserve amounts
    function _cacheReserves(uint256[] memory reserves) internal {
        (uint8 _zeroi, uint8 _targeti) = getIndices();

        uint256 reserveZero = reserves[_zeroi] + totalSupply();
        // Calculate the backdated Target reserve
        uint256 reserveUnderlying = reserves[_targeti].mulDown(_initScale);

        // Caclulate the invariant and store everything
        // TODO
        _lastToken0Reserve = _zeroi == 0 ? reserveZero : reserveUnderlying;
        _lastToken1Reserve = _zeroi == 0 ? reserveUnderlying : reserveZero;
    }

    /* ========== PUBLIC GETTERS ========== */

    /// @notice Get token indices for Zero and Target
    function getIndices() public view returns (uint8 _zeroi, uint8 _targeti) {
        _zeroi = zeroi;
        _targeti = _zeroi == 0 ? 1 : 0;
    }

    /* ========== BALANCER REQUIRED INTERFACE ========== */

    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    /* ========== BALANCER SCALING FUNCTIONS ========== */

    /// @notice Scaling factors for Zero & Target tokens
    function _scalingFactor(bool zero) internal view returns (uint256) {
        return zero ? _scalingFactorZero : _scalingFactorTarget;
    }

    /// @notice Scale number type to 18 decimals if need be
    function _upscale(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount * scalingFactor;
    }

    /// @notice Ensure number type is back in its base decimal if need be, rounding down
    function _downscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount / scalingFactor;
    }

    /// @notice Ensure number type is back in its base decimal if need be, rounding up
    function _downscaleUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return 1 + (amount - 1) / scalingFactor;
    }

    /// @notice Upscale array of token amounts to 18 decimals if need be
    function _upscaleArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = amounts[_zeroi] * _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] * _scalingFactor(false);
    }

    /// @notice Downscale array of token amounts to 18 decimals if need be, rounding down
    function _downscaleDownArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = amounts[_zeroi] / _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] / _scalingFactor(false);
    }

    /// @notice Downscale array of token amounts to 18 decimals if need be, rounding up
    function _downscaleUpArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = 1 + (amounts[_zeroi] - 1) / _scalingFactor(true);
        amounts[_targeti] = 1 + (amounts[_targeti] - 1) / _scalingFactor(false);
    }

    /* ========== MODIFIERS ========== */

    /// Taken from balancer-v2-monorepo/**/WeightedPool2Tokens.sol
    modifier onlyVault(bytes32 poolId_) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId_ == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }
}
