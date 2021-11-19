// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";
import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";
import { Vault } from "@balancer-labs/v2-vault/contracts/Vault.sol";

import { IProtocolFeesCollector } from "@balancer-labs/v2-vault/contracts/interfaces/IProtocolFeesCollector.sol";
import { IMinimalSwapInfoPool } from "@balancer-labs/v2-vault/contracts/interfaces/IMinimalSwapInfoPool.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { IERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import { Errors, _require } from "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";

interface DividerLike {
    function series(
        address, /* adapter */
        uint48 /* maturity */
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
                    YIELD SPACE
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

/// @notice A Yield Space implementation extended such that it allows LPs to deposit
/// (Zero, Yield-bearing asset) – rather than [Zero, Underlying] – while keeping the benefits of
/// standard yield space invariant accounting (ex: [Zero, cDAI] rather than [Zero, DAI])
contract Space is IMinimalSwapInfoPool, BalancerPoolToken {
    using FixedPoint for uint256;

    // Minimum BPT we can have in this pool after initialization
    uint256 public constant MINIMUM_BPT = 1e6;

    // Sense Divider ᗧ···ᗣ···ᗣ··
    address public immutable divider;
    // Adapter address for the associated Sense Series
    address public immutable adapter;
    // Scale value for this asset at first join (i.e. initialization)
    uint256 internal _initScale;
    // Maturity timestamp for associated Series
    uint48 internal immutable _maturity;
    // Zero token index (only two slots in a two token pool, so `targeti` is always just the complement)
    uint8 public zeroi;

    // Balancer pool id (as registered with the Balancer Vault)
    bytes32 internal _poolId;

    // Invariant tracking for Balancer fee calculation
    uint256 internal _lastInvariant;
    uint256 internal _lastToken0Reserve;
    uint256 internal _lastToken1Reserve;

    // Token registered at index zero for this pool
    IERC20 internal immutable _token0;

    // Token registered at index zero for this pool
    IERC20 internal immutable _token1;

    // Factor needed to scale the Zero token to 18 decimals
    uint96 internal immutable _scalingFactorZero;
    // Factor needed to scale the Target token to 18 decimals
    uint96 internal immutable _scalingFactorTarget;

    // Balancer Vault
    IVault internal immutable _vault;
    // Balancer fees collection
    address internal immutable _protocolFeesCollector;

    // Yieldspace config, passed in from space factory
    uint256 public immutable ts;
    uint256 public immutable g1;
    uint256 public immutable g2;

    constructor(
        IVault vault_,
        address _adapter,
        uint48 maturity_,
        address _divider,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) BalancerPoolToken(AdapterLike(_adapter).name(), AdapterLike(_adapter).symbol()) {
        bytes32 poolId = vault_.registerPool(IVault.PoolSpecialization.TWO_TOKEN);

        (address zero, , , , , , , , ) = DividerLike(_divider).series(_adapter, maturity_);
        address target = AdapterLike(_adapter).getTarget();
        IERC20[] memory tokens = new IERC20[](2);

        // Ensure the array of tokens is correctly ordered
        zeroi = zero < target ? 0 : 1;
        tokens[zeroi] = IERC20(zero);
        tokens[zeroi == 0 ? 1 : 0] = IERC20(target);
        vault_.registerTokens(poolId, tokens, new address[](2));

        // Base balancer pool config
        _vault = vault_;
        _poolId = poolId;
        _token0 = tokens[0];
        _token1 = tokens[1];
        _protocolFeesCollector = address(vault_.getProtocolFeesCollector());

        _scalingFactorZero = uint96(10**(18 - ERC20(zero).decimals()));
        _scalingFactorTarget = uint96(10**(18 - ERC20(target).decimals()));

        // Yieldspace config
        g1 = _g1; // fees are baked into factors `g1` & `g2`,
        g2 = _g2; // see the "Fees" section of the yieldspace paper
        ts = _ts;

        // Sense-specific slots
        _maturity = maturity_;
        divider = _divider;
        adapter = _adapter;
    }

    function onJoinPool(
        bytes32 poolId_,
        address, /* _sender */
        address _recipient,
        uint256[] memory _reserves,
        uint256, /* _lastChangeBlock */
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(poolId_) returns (uint256[] memory, uint256[] memory) {
        // Space does not have multiple join types like other Balancer pools,
        // its `joinPool` always has the behavior of `EXACT_TOKENS_IN_FOR_BPT_OUT`

        require(_maturity >= block.timestamp, "Cannot join a Pool post maturity");

        uint256[] memory _reqAmountsIn = abi.decode(_userData, (uint256[]));

        // Upscale both amounts in to 18 decimals
        _upscaleArray(_reqAmountsIn);
        (uint8 _zeroi, uint8 _targeti) = getIndices();

        if (totalSupply() == 0) {
            // Set the scale all future deposits will be normed back to
            _initScale = AdapterLike(adapter).scale();

            // Convert target balance into Underlying
            // note: We can assume scale values will always be 18 decimals
            uint256 underlyingIn = (_reqAmountsIn[_targeti] * _initScale) / 1e18;
            // Initial BPT minted is equal to the vaule of Target in Underlying terms deposited
            uint256 bptAmountOut = underlyingIn - MINIMUM_BPT;

            // Just like weighted pool 2 token from the balancer v2 monorepo,
            // we lock MINIMUM_BPT in by minting it for the zero address –
            // this reduces potential issues with rounding and ensures that this code will only be executed once
            _mintPoolTokens(address(0), MINIMUM_BPT);
            _mintPoolTokens(_recipient, bptAmountOut);

            // For the first join, we don't pull any Zeros, regardless of what the caller requested –
            // this starts this pool off as "Underlying" only, as speified in the yield space paper
            delete _reqAmountsIn[_zeroi];

            // Amounts entering the Pool, so we round up
            _downscaleUp(_reqAmountsIn[_targeti], _scalingFactor(false));

            return (_reqAmountsIn, new uint256[](2));
        } else {
            (uint256 bptToMint, uint256[] memory _amountsIn) = _tokensInForBptOut(_reqAmountsIn, _reserves);

            _mintPoolTokens(_recipient, bptToMint);

            // Amounts entering the Pool, so we round up
            _downscaleUpArray(_amountsIn);

            // Calculate fees due before updating reserves to determine invariant growth from just swap fees
            if (_protocolSwapFeePercentage != 0) {
                // Balancer fealty
                _mintPoolTokens(_protocolFeesCollector, _dueBptFee(_reserves, _protocolSwapFeePercentage));
            }

            // Update reserves
            _reserves[0] += _amountsIn[0];
            _reserves[1] += _amountsIn[1];

            // Cache new invariant and reserves
            _cacheInvariantAndReserves(_reserves);

            // Inspired by PR #990 in the balancer monorepo, we always return zero
            // dueProtocolFeeAmounts to the Vault and instead mint BPT directly to the protocolFeeCollector
            return (_amountsIn, new uint256[](2));
        }
    }

    function onExitPool(
        bytes32 poolId_,
        address _sender,
        address, /* _recipient */
        uint256[] memory _reserves,
        uint256, /* _lastChangeBlock */
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(poolId_) returns (uint256[] memory, uint256[] memory) {
        // Space does not have multiple exit types like other Balancer pools,
        // its `exitPool` always has the behavior of `EXACT_BPT_IN_FOR_TOKENS_OUT`

        _upscaleArray(_reserves);

        uint256[] memory _amountsOut = new uint256[](2);

        uint256 _bptAmountIn = abi.decode(_userData, (uint256));
        uint256 _pctPool = _bptAmountIn.divDown(totalSupply());

        _amountsOut[0] = _reserves[0].mulDown(_pctPool);
        _amountsOut[1] = _reserves[1].mulDown(_pctPool);

        _burnPoolTokens(_sender, _bptAmountIn);

        _downscaleDownArray(_amountsOut);

        // Calculate fees due before updating reserves to determine invariant growth from just swap fees
        if (_protocolSwapFeePercentage != 0) {
            // Balancer fealty
            _mintPoolTokens(_protocolFeesCollector, _dueBptFee(_reserves, _protocolSwapFeePercentage));
        }

        // Update reserves
        _reserves[0] -= _amountsOut[0];
        _reserves[1] -= _amountsOut[1];

        _cacheInvariantAndReserves(_reserves);

        return (_amountsOut, new uint256[](2));
    }

    function onSwap(
        SwapRequest memory _request,
        uint256 _reservesTokenIn,
        uint256 _reservesTokenOut
    ) external override returns (uint256) {
        bool token0In = _request.tokenIn == _token0;
        bool zeroIn = token0In ? zeroi == 0 : zeroi == 1;

        uint96 scalingFactorTokenIn = _scalingFactor(zeroIn);
        uint96 scalingFactorTokenOut = _scalingFactor(!zeroIn);

        _reservesTokenIn = _upscale(_reservesTokenIn, scalingFactorTokenIn);
        _reservesTokenOut = _upscale(_reservesTokenOut, scalingFactorTokenOut);

        // Sense Adapter Scale value (Underyling per Target)
        uint256 scale = AdapterLike(adapter).scale();

        if (zeroIn) {
            // Add LP supply to Zero reserves as suggested by the yield space paper
            _reservesTokenIn += totalSupply();
            // Remove all new underlying accured while the Target has been in this pool from Target reserve accounting,
            // then convert the remaining Target into Underlying.
            // `excess = targetReserves * scale / _initScale - targetReserves`
            // `adjustedTargetReserves = targetReserves - excess`
            // `adjustedUnderlyingReserves = adjustedTargetReserves * scale`
            // simplified to: `(2 * targetReserves - target reserves * scale / initScale) * scale`
            _reservesTokenOut = (2 * _reservesTokenOut - (_reservesTokenOut * scale) / _initScale).mulDown(scale);
        } else {
            _reservesTokenIn = (2 * _reservesTokenIn - (_reservesTokenIn * scale) / _initScale).mulDown(scale);
            _reservesTokenOut += totalSupply();
        }

        if (_request.kind == IVault.SwapKind.GIVEN_IN) {
            _request.amount = _upscale(_request.amount, scalingFactorTokenIn);

            uint256 amountOut = _onSwap(zeroIn, true, _request.amount, _reservesTokenIn, _reservesTokenOut);

            // Amount out, so downscale down to avoid sending too much out by 1
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            _request.amount = _upscale(_request.amount, scalingFactorTokenOut);

            uint256 amountIn = _onSwap(zeroIn, false, _request.amount, _reservesTokenIn, _reservesTokenOut);

            // Amount in, so downscale up to ensure there's enough
            return _downscaleUp(amountIn, scalingFactorTokenIn);
        }
    }

    /// @notice Internal helpers ----

    function _dueBptFee(uint256[] memory _reserves, uint256 _protocolSwapFeePercentage) internal returns (uint256) {
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        // Invariant growth from time only
        uint256 _currentAdjInvariant = _lastToken0Reserve.powDown(a) + _lastToken1Reserve.powDown(a);
        // Actual invariant
        uint256 _currentInvariant = _reserves[0].powDown(a) + _reserves[1].powDown(a);

        uint256 denom = _lastInvariant.mulDown(_currentAdjInvariant.divUp(_lastInvariant));
        return
            _currentInvariant.divDown(denom).sub(FixedPoint.ONE).mulDown(totalSupply()).mulDown(
                _protocolSwapFeePercentage
            );
    }

    function _tokensInForBptOut(uint256[] memory _reqAmountsIn, uint256[] memory _reserves)
        internal
        returns (uint256, uint256[] memory)
    {
        uint256 _scale = AdapterLike(adapter).scale();
        uint256[] memory amountsIn = new uint256[](2);

        (uint8 _zeroi, uint8 _targeti) = getIndices();
        (uint256 _zeroReserves, uint256 _targetReserves) = (_reserves[_zeroi], _reserves[_targeti]);
        (uint256 _reqZerosIn, uint256 _reqTargetIn) = (_reqAmountsIn[_zeroi], _reqAmountsIn[_targeti]);

        // Calculate the excess Target, remove it from the requested amount in, then convert the remaining Target into Underlying
        uint256 _reqUnderlyingIn = (2 * _reqTargetIn - (_reqTargetIn * _scale) / _initScale).mulDown(_scale);

        // If we pulled all the requested Underlying, what pct of the pool do we get?
        // note: Current balance of Target will always be > 1 by the time this is called
        uint256 pctUnderlying = _reqUnderlyingIn.divDown((_targetReserves * _initScale) / _scale);

        // If the pool has been initialized, but there aren't yet any Zeros in it,
        // we pull the entire offered Target and mint lp shares proportionally
        if (_zeroReserves == 0) {
            uint256 bptToMint = (totalSupply() * _reqUnderlyingIn) / ((_targetReserves * _initScale) / _scale);
            amountsIn[_targeti] = _reqTargetIn;

            return (bptToMint, amountsIn);
        } else {
            uint256 pctZeros = _reqZerosIn.divDown(_reserves[_zeroi]);

            // Determine which amount in is our limiting factor
            if (pctUnderlying < pctZeros) {
                uint256 bptToMint = totalSupply().mulDown(pctUnderlying);

                amountsIn[_zeroi] = _zeroReserves.mulDown(pctUnderlying);
                amountsIn[_targeti] = _reqTargetIn;

                return (bptToMint, amountsIn);
            } else {
                uint256 bptToMint = totalSupply().mulDown(pctZeros);

                amountsIn[_zeroi] = _reqZerosIn;
                amountsIn[_targeti] = _targetReserves.mulDown(pctZeros);

                return (bptToMint, amountsIn);
            }
        }
    }

    function _onSwap(
        bool _zeroIn,
        bool _givenIn,
        uint256 _amountDelta,
        uint256 _reservesTokenIn,
        uint256 _reservesTokenOut
    ) internal view returns (uint256) {
        // x_pre = token in reserves pre swap
        // y_pre = token out reserves pre swap

        // Seconds until maturity
        // After maturity, still allow users to transfer using a constant sum pool
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;

        // `t` from the yield space paper (`ttm` adjusted by some factor `ts`)
        uint256 t = ts.mulDown(ttm);

        // `t` with fees baked in
        uint256 a = (_zeroIn ? g2 : g1).mulUp(t).complement();

        // x1 = x_pre ^ a
        uint256 x1 = _reservesTokenIn.powDown(a);

        // y1 = y_pre ^ a
        uint256 y1 = _reservesTokenOut.powDown(a);

        // y2 = x_post ^ a
        // x2 = y_post ^ a
        uint256 xOrY2 = (_givenIn ? _reservesTokenIn + _amountDelta : _reservesTokenOut - _amountDelta).powDown(a);

        // x1 + y1 = xOrY2 + post ^ a
        // -> post ^ a = x1 + y1 - x2
        // -> post = (x1 + y1 - xOrY2) ^ (1 / a)
        uint256 post = (x1 + y1 - xOrY2).powDown(FixedPoint.ONE.divDown(a));
        require(_givenIn ? _reservesTokenOut > post : post > _reservesTokenIn, "Too few reserves");

        // amount out given in = y_pre - y_post
        // amount in given out = x_post - x_pre
        return _givenIn ? _reservesTokenOut.sub(post) : post.sub(_reservesTokenIn);
    }

    /// @notice Public getter ----

    // Get token indices for Zero and Target
    function getIndices() public view returns (uint8 _zeroi, uint8 _targeti) {
        _zeroi = zeroi; // a regrettable SLOAD = 〰 =
        _targeti = _zeroi == 0 ? 1 : 0;
    }

    /// @notice Balancer-required interfaces ----

    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    function _cacheInvariantAndReserves(uint256[] memory _reserves) internal {
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        _lastInvariant = _reserves[0].powDown(a) + _reserves[1].powDown(a);
        _lastToken0Reserve = _reserves[0];
        _lastToken1Reserve = _reserves[1];
    }

    /// @notice Fixed point decimal shifting methods from Balancer ----

    // scaling factors for Zero & Target tokens
    function _scalingFactor(bool zero) internal view returns (uint96) {
        return zero ? _scalingFactorZero : _scalingFactorTarget;
    }

    // Scale number type to 18 decimals if need be
    function _upscale(uint256 amount, uint96 scalingFactor) internal pure returns (uint256) {
        return amount * scalingFactor;
    }

    // Ensure number type is back in its base decimals (if less than 18)
    function _downscaleDown(uint256 amount, uint96 scalingFactor) internal returns (uint256) {
        return amount / scalingFactor; // rounds down
    }

    function _downscaleUp(uint256 amount, uint96 scalingFactor) internal returns (uint256) {
        return 1 + (amount - 1) / scalingFactor; // rounds up
    }

    function _upscaleArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = amounts[_zeroi] * _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] * _scalingFactor(false);
    }

    function _downscaleDownArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = amounts[_zeroi] / _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] / _scalingFactor(false);
    }

    function _downscaleUpArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi] = 1 + (amounts[_zeroi] - 1) / _scalingFactor(true);
        amounts[_targeti] = 1 + (amounts[_targeti] - 1) / _scalingFactor(false);
    }

    // Taken from balancer-v2-monorepo/**/WeightedPool2Tokens.sol
    modifier onlyVault(bytes32 poolId_) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId_ == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }
}
