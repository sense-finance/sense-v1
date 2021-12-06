// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";
import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";

import { IProtocolFeesCollector } from "@balancer-labs/v2-vault/contracts/interfaces/IProtocolFeesCollector.sol";
import { IMinimalSwapInfoPool } from "@balancer-labs/v2-vault/contracts/interfaces/IMinimalSwapInfoPool.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { IERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import { Errors, _require } from "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";

interface DividerLike {
    function series(
        address, /* adapter */
        uint256 /* maturity */
    )
        external
        virtual
        returns (
            address, /* zero */
            address, /* claim */
            address, /* sponsor */
            uint256, /* reward */
            uint256, /* iscale */
            uint256, /* mscale */
            uint256, /* maxscale */
            uint128, /* issuance */
            uint128 /* tilt */
        );
}

interface AdapterLike {
    function underlying() external returns (address);

    function scale() external returns (uint256);

    function getTarget() external returns (address);

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

/// @notice A Yieldspace implementation extended such that it allows LPs to deposit
/// [Zero, Yield-bearing asset], rather than [Zero, Underlying], while keeping the benefits of
/// standard yieldspace invariant accounting (ex: it can hold [Zero, cDAI] rather than [Zero, DAI])
/// @dev We use much more internal storage here than in other Sense contracts because it
/// conforms to Balancer's own style, and we're using several Balancer functions that play nicer this way.
contract Space is IMinimalSwapInfoPool, BalancerPoolToken {
    using FixedPoint for uint256;

    /* ========== CONSTANTS ========== */

    /// @notice Minimum BPT we can have in this pool after initialization
    uint256 public constant MINIMUM_BPT = 1e6;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense Divider ᗧ···ᗣ···ᗣ··
    address public immutable divider;

    /// @notice Sense Adapter address for the associated Series
    address public immutable adapter;

    /// @dev Maturity timestamp for associated Series
    uint48 public immutable maturity;

    /// @notice Zero token index (only two tokens in this pool, so `targeti` is always just the complement)
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
    uint256 internal _lastInvariant;
    uint256 internal _lastToken0Reserve;
    uint256 internal _lastToken1Reserve;

    constructor(
        IVault vault,
        address _adapter,
        uint48 _maturity,
        address _divider,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) BalancerPoolToken(AdapterLike(_adapter).name(), AdapterLike(_adapter).symbol()) {
        bytes32 poolId = vault.registerPool(IVault.PoolSpecialization.TWO_TOKEN);

        (address zero, , , , , , , , ) = DividerLike(_divider).series(_adapter, uint256(_maturity));
        address target = AdapterLike(_adapter).getTarget();
        IERC20[] memory tokens = new IERC20[](2);

        // Ensure that the array of tokens is correctly ordered
        uint8 _zeroi = zero < target ? 0 : 1;
        tokens[_zeroi] = IERC20(zero);
        tokens[_zeroi == 0 ? 1 : 0] = IERC20(target);
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

        // Set Sense-specific slots
        maturity = _maturity;
        divider = _divider;
        adapter = _adapter;
        zeroi = _zeroi;
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
        // instead, its `joinPool` always behaves like Balancer's `EXACT_TOKENS_IN_FOR_BPT_OUT`

        require(maturity >= block.timestamp, "Pool past maturity");

        uint256[] memory reqAmountsIn = abi.decode(userData, (uint256[]));

        // Upscale both requiested amounts and reserves to 18 decimals
        _upscaleArray(reserves);
        _upscaleArray(reqAmountsIn);
        (uint8 zeroi, uint8 targeti) = getIndices();

        if (totalSupply() == 0) {
            uint256 initScale = AdapterLike(adapter).scale();

            // Convert target balance into Underlying
            // note: We assume scale values will always be 18 decimals
            uint256 underlyingIn = (reqAmountsIn[targeti] * initScale) / 1e18;

            // Initial BPT minted is equal to the vaule of the deposited Target in Underlying terms
            uint256 bptAmountOut = underlyingIn - MINIMUM_BPT;

            // Just like weighted pool 2 token from the balancer v2 monorepo,
            // we lock MINIMUM_BPT in by minting it for the zero address –
            // this reduces potential issues with rounding and ensures that this code will only be executed once
            _mintPoolTokens(address(0), MINIMUM_BPT);
            _mintPoolTokens(recipient, bptAmountOut);

            // Amounts entering the Pool, so we round up
            _downscaleUpArray(reqAmountsIn);

            // Set the scale value all future deposits will be backdated to
            _initScale = initScale;

            // For the first join, we don't pull any Zeros, regardless of what the caller requested –
            // this starts this pool off as synthetic Underlying only, as the yieldspace invariant expects
            delete reqAmountsIn[zeroi];

            _cacheInvariantAndReserves(reserves);

            return (reqAmountsIn, new uint256[](2));
        } else {
            (uint256 bptToMint, uint256[] memory amountsIn) = _tokensInForBptOut(reqAmountsIn, reserves);

            _mintPoolTokens(recipient, bptToMint);

            // Amounts entering the Pool, so we round up
            _downscaleUpArray(amountsIn);

            // Calculate fees due before updating reserves to determine invariant growth from just swap fees
            if (protocolSwapFeePercentage != 0) {
                _mintPoolTokens(_protocolFeesCollector, _bptFeeDue(reserves, protocolSwapFeePercentage));
            }

            // Update reserves for invariant caching
            reserves[0] += amountsIn[0];
            reserves[1] += amountsIn[1];

            // Cache new invariant and reserves, post join
            _cacheInvariantAndReserves(reserves);

            // Inspired by PR #990 in balancer-v2-monorepo, we always return zero dueProtocolFeeAmounts 
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
        // instead, its `exitPool` always behaves like Balancer's `EXACT_BPT_IN_FOR_TOKENS_OUT`

        // Upscale reserves to 18 decimals
        _upscaleArray(reserves);

        // Determine what percentage of the pool the BPT being passed inis
        uint256 bptAmountIn = abi.decode(userData, (uint256));
        uint256 pctPool = bptAmountIn.divDown(totalSupply());

        // Calculate the amount of tokens owed in return for giving that amount of BPT in
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[0] = reserves[0].mulDown(pctPool);
        amountsOut[1] = reserves[1].mulDown(pctPool);

        // `sender` pays for the liquidity
        _burnPoolTokens(sender, bptAmountIn);

        // Amounts leaving the Pool, so we round down
        _downscaleDownArray(amountsOut);

        // Calculate fees due before updating reserves to determine invariant growth from just swap fees
        if (protocolSwapFeePercentage != 0) {
            // Balancer fealty
            _mintPoolTokens(_protocolFeesCollector, _bptFeeDue(reserves, protocolSwapFeePercentage));
        }

        // Update reserves for invariant caching
        reserves[0] -= amountsOut[0];
        reserves[1] -= amountsOut[1];

        // Cache new invariant and reserves, post exit
        _cacheInvariantAndReserves(reserves);

        return (amountsOut, new uint256[](2));
    }

    function onSwap(
        SwapRequest memory request,
        uint256 reservesTokenIn,
        uint256 reservesTokenOut
    ) external override returns (uint256) {
        bool token0In = request.tokenIn == _token0;
        bool zeroIn = token0In ? zeroi == 0 : zeroi == 1;

        // Upscale reserves to 18 decimals
        uint256 scalingFactorTokenIn = _scalingFactor(zeroIn);
        uint256 scalingFactorTokenOut = _scalingFactor(!zeroIn);
        reservesTokenIn = _upscale(reservesTokenIn, scalingFactorTokenIn);
        reservesTokenOut = _upscale(reservesTokenOut, scalingFactorTokenOut);

        uint256 scale = AdapterLike(adapter).scale();

        if (zeroIn) {
            // Add LP supply to Zero reserves, as suggested by the yieldspace paper
            reservesTokenIn += totalSupply();
            // Calculate the excess Target (Target value due only to scale growth since initialization), 
            // remove it from the requested amount in, 
            // then convert the remaining Target into Underlying
            reservesTokenOut = scale > _initScale ? 
                (2 * reservesTokenOut - reservesTokenOut / (scale - _initScale)).mulDown(scale) :
                reservesTokenOut.mulDown(scale);
        } else {
            // Calculate the excess Target (Target value due only to scale growth since initialization), 
            // remove it from the requested amount in, 
            // then convert the remaining Target into Underlying
            reservesTokenIn = scale > _initScale ? 
                (2 * reservesTokenIn - reservesTokenIn / (scale - _initScale)).mulDown(scale) :
                reservesTokenIn.mulDown(scale);

            // Add LP supply to Zero reserves, as suggested by the yieldspace paper
            reservesTokenOut += totalSupply();
        }

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            request.amount = _upscale(request.amount, scalingFactorTokenIn);

            uint256 amountOut = _onSwap(zeroIn, true, request.amount, reservesTokenIn, reservesTokenOut);

            // Amount out, so we round down to avoid sending too much out by some dust amount
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            request.amount = _upscale(request.amount, scalingFactorTokenOut);

            uint256 amountIn = _onSwap(zeroIn, false, request.amount, reservesTokenIn, reservesTokenOut);

            // Amount in, so we round up
            return _downscaleUp(amountIn, scalingFactorTokenIn);
        }
    }

    /* ========== INTERNAL JOIN/SWAP ACCOUNTING ========== */

    /// @notice Calculate the max amount of BPT that can be minted from the requested amounts in, 
    // given the ratio of the reserves, and assuming we don't make any swaps
    function _tokensInForBptOut(uint256[] memory reqAmountsIn, uint256[] memory _reserves)
        internal
        returns (uint256, uint256[] memory)
    {
        // Disambiguate reserves and requested amount wrt token type
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        (uint256 zeroReserves, uint256 targetReserves) = (reserves[_zeroi], reserves[_targeti]);
        (uint256 reqZerosIn, uint256 reqTargetIn) = (reqAmountsIn[_zeroi], reqAmountsIn[_targeti]);

        uint256 scale = AdapterLike(adapter).scale();

        // Calculate the excess Target (Target value due only to scale growth since initialization), 
        // remove it from the requested amount in, 
        // then convert the remaining Target into Underlying
        uint256 reqUnderlyingIn = (2 * reqTargetIn - (reqTargetIn * scale) / _initScale).mulDown(scale);

        uint256[] memory amountsIn = new uint256[](2);

        // If the pool has been initialized, but there aren't yet any Zeros in it,
        // we pull the entire offered Target and mint lp shares proportionally
        if (zeroReserves == 0) {
            uint256 bptToMint = (totalSupply() * reqUnderlyingIn) / ((targetReserves * _initScale) / scale);
            amountsIn[_targeti] = reqTargetIn;

            return (bptToMint, amountsIn);
        } else {
            // Caclulate the percentage of the pool we'd get if we pulled all of the requested Underlying in
            // note: The current reserves of Target will always be above zero by the time this line is reached
            uint256 pctUnderlying = reqUnderlyingIn.divDown((targetReserves * _initScale) / scale);

            // Caclulate the percentage of the pool we'd get if we pulled all of the requested Zeros in
            uint256 pctZeros = reqZerosIn.divDown(_reserves[_zeroi]);

            // Determine which amount in is our limiting factor
            if (pctUnderlying < pctZeros) {
                // If it's Underlying, pull the entire requested Target amount in,
                // and pull Zeros in at the percetage of the requested Underlying
                uint256 bptToMint = totalSupply().mulDown(pctUnderlying);

                amountsIn[_zeroi] = zeroReserves.mulDown(pctUnderlying);
                amountsIn[_targeti] = reqTargetIn;

                return (bptToMint, amountsIn);
            } else {
                // If it's Zeros, pull the entire requested Zero amount in,
                // and pull Target in at the percetage of the requested Zeros
                uint256 bptToMint = totalSupply().mulDown(pctZeros);

                amountsIn[_zeroi] = reqZerosIn;
                // TODO:
                amountsIn[_targeti] = targetReserves.mulDown(pctZeros);

                return (bptToMint, amountsIn);
            }
        }
    }

    /// @notice Calculate the missing variable in the yield space equation given the direction (Zero in vs. out)
    function _onSwap(
        bool zeroIn,
        bool givenIn,
        uint256 amountDelta,
        uint256 reservesTokenIn,
        uint256 reservesTokenOut
    ) internal returns (uint256) {
        // xPre = token in reserves pre swap
        // yPre = token out reserves pre swap

        // Seconds until maturity, in 18 decimals
        // After maturity, this pool becomes a pure constant sum AMM
        uint256 ttm = maturity > block.timestamp ? uint256(maturity - block.timestamp) * FixedPoint.ONE : 0;

        // Time shifted partial `t` from the yieldspace paper (`ttm` adjusted by some factor `ts`)
        uint256 t = ts.mulDown(ttm);

        // Full `t` with fees baked in
        uint256 a = (zeroIn ? g2 : g1).mulUp(t).complement();

        // x1 = xPre ^ a
        uint256 x1 = reservesTokenIn.powDown(a);

        // y1 = yPre ^ a
        uint256 y1 = reservesTokenOut.powDown(a);

        // y2 = yPost ^ a
        // x2 = xPost ^ a
        // If we're given an amount in, add it to the reserves in,
        // if we're given an amount out, subtract it from the reserves out
        uint256 xOrY2 = (givenIn ? reservesTokenIn + amountDelta : reservesTokenOut - amountDelta).powDown(a);
        // require(!givenIn || xOrY2 > reservesTokenIn, "Swap amount too small");

        // x1 + y1 = xOrY2 + xOrYPost ^ a
        // -> xOrYPost ^ a = x1 + y1 - x2
        // -> xOrYPost = (x1 + y1 - xOrY2) ^ (1 / a)
        uint256 xOrYPost = (x1 + y1 - xOrY2).powDown(FixedPoint.ONE.divDown(a));
        require(givenIn ? reservesTokenOut > xOrYPost : xOrYPost > reservesTokenIn, "Too few reserves");

        // amount out given in = yPre - yPost
        // amount in given out = xPost - xPre
        return givenIn ? reservesTokenOut.sub(xOrYPost) : xOrYPost.sub(reservesTokenIn);
    }

    /* ========== PROTOCOL FEE HELPERS ========== */

    /// @notice Determine the growth in the yieldspace invariant due to a swap fees, only
    /// @dev This can't be a view function b/c `Adapter.scale` is not a view function
    function _bptFeeDue(uint256[] memory _reserves, uint256 _protocolSwapFeePercentage) internal returns (uint256) {
        uint256 ttm = maturity > block.timestamp ? uint256(maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        // Invariant growth from time only
        uint256 _currentAdjInvariant = _lastToken0Reserve.powDown(a) + _lastToken1Reserve.powDown(a);

        uint256 _scale = AdapterLike(adapter).scale();
        (uint8 _zeroi, uint8 _targeti) = getIndices();

        // Actual invariant
        uint256 x = (_reserves[_zeroi] + totalSupply()).powDown(a);
        // Calculate the backdated Target reserves in Underyling terms
        uint256 y = _scale > _initScale
            ? (2 * _reserves[_targeti] - _reserves[_targeti] / (_scale - _initScale)).mulDown(_scale)
            : _reserves[_targeti].mulDown(_scale);

        return
            (x + y)
                .divDown(_lastInvariant.mulDown(_currentAdjInvariant.divUp(_lastInvariant)))
                .sub(FixedPoint.ONE)
                .mulDown(totalSupply())
                .mulDown(_protocolSwapFeePercentage);
    }

    /// @notice Cache the given reserve amounts and use them to calculate the current invariant,
    /// without taking the fee factors `g1` and `g2` into account
    function _cacheInvariantAndReserves(uint256[] memory reserves) internal {
        uint256 ttm = maturity > block.timestamp ? uint256(maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        (uint8 _zeroi, uint8 _targeti) = getIndices();
        uint256 _scale = AdapterLike(adapter).scale();

        uint256 reserveZero = reserves[_zeroi] + totalSupply();
        // Calculate the backdated Target reserves in Underyling terms
        uint256 reserveUnderlying = _scale > _initScale
            ? (2 * reserves[_targeti] - reserves[_targeti] / (_scale - _initScale)).mulDown(_scale)
            : reserves[_targeti].mulDown(_scale);

        // Caclulate the invariant and store everything
        _lastInvariant = reserveZero.powDown(a) + reserveUnderlying.powDown(a);
        _lastToken0Reserve = _zeroi == 0 ? reserveZero : reserveUnderlying;
        _lastToken1Reserve = _zeroi == 0 ? reserveUnderlying : reserveZero;
    }

    /* ========== PUBLIC GETTER ========== */

    /// @notice Get token indices for Zero and Target
    function getIndices() public view returns (uint8 _zeroi, uint8 _targeti) {
        _zeroi = zeroi; // a regrettable SLOAD
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
    function _downscaleDown(uint256 amount, uint256 scalingFactor) internal returns (uint256) {
        return amount / scalingFactor;
    }

    /// @notice Ensure number type is back in its base decimal if need be, rounding up
    function _downscaleUp(uint256 amount, uint256 scalingFactor) internal returns (uint256) {
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
