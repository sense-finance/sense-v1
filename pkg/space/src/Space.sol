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

/// TODO: exact amount in for join
/// TODO: max EXACT_TOKENS_IN_FOR_BPT_OUT

/// @notice A Yield Space implementation extended such that it allows LPs to deposit
/// [Zero, wrapped yield-bearing underlying], rather than [Zero, underlying] while keeping
/// the standard yield space invariant accounting (ex: [Zero, cDAI] rather than [Zero, DAI])
contract Space is IMinimalSwapInfoPool, BalancerPoolToken {
    using FixedPoint for uint256;

    // minimum BPT we can have in this pool after initialization
    uint256 public constant MINIMUM_BPT = 1e6;

    // Sense Divider ᗧ···ᗣ···ᗣ··
    address public immutable divider;
    // adapter address for the associated Sense Series
    address public immutable adapter;
    // scale value for this asset at first join (i.e. initialization)
    uint256 internal _initScale;
    // maturity timestamp for associated Series
    uint48 internal immutable _maturity;
    // Zero token index (only two slots in a two token pool, so `targeti` is always just the complement)
    uint8 public zeroi;

    // Balancer pool id (registered with the main Balancer Vault)
    bytes32 internal _poolId;
    // bytes32 internal _miscData;
    uint256 internal _lastInvariant;
    uint256 internal _lastToken0Reserve;
    uint256 internal _lastToken1Reserve;

    // token registered at index zero for this pool
    IERC20 internal immutable _token0;

    // token registered at index zero for this pool
    IERC20 internal immutable _token1;

    // factor needed to scale the Zero token to 18 decimals
    uint96 internal immutable _scalingFactorZero;
    // factor needed to scale the Target token to 18 decimals
    uint96 internal immutable _scalingFactorTarget;

    // main Balancer Vault
    IVault internal immutable _vault;
    // the address we'll send Balancer due fees to
    address internal immutable _protocolFeesCollector;

    // yieldspace config, passed in from space factory
    uint256 public immutable ts;
    uint256 public immutable g1;
    uint256 public immutable g2;

    // event OracleEnabledChanged(bool enabled);

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

        // ensure the array of tokens is correctly ordered
        zeroi = zero < target ? 0 : 1;
        tokens[zeroi] = IERC20(zero);
        tokens[zeroi == 0 ? 1 : 0] = IERC20(target);
        vault_.registerTokens(poolId, tokens, new address[](2));

        // base balancer pool config
        _vault = vault_;
        _poolId = poolId;
        _token0 = tokens[0];
        _token1 = tokens[1];
        _protocolFeesCollector = address(vault_.getProtocolFeesCollector());

        _scalingFactorZero = uint96(10**(18 - ERC20(zero).decimals()));
        _scalingFactorTarget = uint96(10**(18 - ERC20(target).decimals()));

        // yieldspace config
        g1 = _g1; // fees are baked into scaling factors `g1` & `g2`
        g2 = _g2; // see the "Fees" section of the yieldspace paper
        ts = _ts;

        // sense-specific slots
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
        require(_maturity >= block.timestamp, "Cannot join a Pool after maturity");

        // this join always behaves like a Balancer `EXACT_TOKENS_IN_FOR_BPT_OUT`

        uint256[] memory _reqAmountsIn = abi.decode(_userData, (uint256[]));

        // upscale both balances to 18 decimals
        _upscaleArray(_reqAmountsIn);
        (uint8 _zeroi, uint8 _targeti) = getIndices();

        if (totalSupply() == 0) {
            // set the scale all future deposits will be backfilled to
            _initScale = AdapterLike(adapter).scale();

            // convert target balance to underlying
            // note: we can assume scale values will always be 18 decimals
            uint256 underlyingIn = (_reqAmountsIn[_targeti] * _initScale) / 1e18;
            // initial BPT minted is equal to the amount of underlying deposited
            uint256 bptAmountOut = underlyingIn - MINIMUM_BPT;

            // just like weighted pool 2 token from the balancer v2 monorepo,
            // we lock MINIMUM_BPT in by minting it for the zero address –
            // this reduces potential issues with rounding and ensures that this code path will only be traveled once
            _mintPoolTokens(address(0), MINIMUM_BPT);
            _mintPoolTokens(_recipient, bptAmountOut);

            // for the first join, we don't pull any Zeros, regardless of what the caller requested –
            // this starts this pool off as "underlying" only, as speified in the yield space paper
            delete _reqAmountsIn[_zeroi];

            // amounts entering the Pool, so we round up
            _downscaleUpArray(_reqAmountsIn);

            return (_reqAmountsIn, new uint256[](2));
        } else {
            (uint256 bptToMint, uint256[] memory _amountIn) = _determineBptOut(_reqAmountsIn, _reserves);

            _mintPoolTokens(_recipient, bptToMint);

            // amounts entering the Pool, so we round up
            _downscaleUpArray(_amountIn);

            // _mintPoolTokens(address(_protocolFeesCollector), bptToMint);
            _mutateAmounts(_reserves, _amountIn, FixedPoint.add);

            if (_protocolSwapFeePercentage != 0) {
                uint256 _bptFee = _determineBptFee(_reserves, _protocolSwapFeePercentage);

                // balancer fealty
                _mintPoolTokens(_protocolFeesCollector, _bptFee);
            }

            _cacheInvariantAndReserves(_reserves);

            // inspired by PR #990 in the balancer monorepo,
            // we always return zero dueProtocolFeeAmounts to the Vault and instead mint BPT
            // directly to the protocolFeeCollector
            return (_amountIn, new uint256[](2));
        }
    }

    function _determineBptOut(uint256[] memory _reqAmountsIn, uint256[] memory _reserves)
        internal
        returns (uint256, uint256[] memory)
    {
        uint256 scale = AdapterLike(adapter).scale();
        uint256[] memory amountsIn = new uint256[](2);

        (uint8 _zeroi, uint8 _targeti) = getIndices();
        (uint256 _zeroReserves, uint256 _targetReserves) = (_reserves[_zeroi], _reserves[_targeti]);
        (uint256 _reqZerosIn, uint256 _reqTargetIn) = (_reqAmountsIn[_zeroi], _reqAmountsIn[_targeti]);

        // calculate the excess Target, remove it from the request, then convert the remaining Target into underlying
        uint256 _reqUnderlyingIn = (2 * _reqTargetIn - (_reqTargetIn * scale) / _initScale).mulDown(scale);

        // if we pulled all the requested underlying, what pct of the pool do we get?
        // current balance of Target will always be > 1 by the time this is called
        uint256 pctUnderlying = _reqUnderlyingIn.divDown((_targetReserves * _initScale) / scale);

        // if the pool has been initialized, but there aren't yet any Zeros in it
        // we pull the entire offered Target and mint lp shares proportionally
        if (_zeroReserves == 0) {
            uint256 bptToMint = (totalSupply() * _reqUnderlyingIn) / ((_targetReserves * _initScale) / scale);
            amountsIn[_targeti] = _reqTargetIn;

            return (bptToMint, amountsIn);
        } else {
            uint256 pctZeros = _reqZerosIn.divDown(_reserves[_zeroi]);

            // determine which amount in is our limiting factor
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

    function onExitPool(
        bytes32 poolId_,
        address _sender,
        address _recipient,
        uint256[] memory _reserves,
        uint256, /* _lastChangeBlock */
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(poolId_) returns (uint256[] memory, uint256[] memory) {
        // This method does not have different exit types,
        // it always behaves like the weighted2token pool's EXACT_BPT_IN_FOR_TOKENS_OUT

        _upscaleArray(_reserves);

        uint256[] memory _amountsOut = new uint256[](2);

        uint256 _bptAmountIn = abi.decode(_userData, (uint256));
        uint256 _pctPool = _bptAmountIn.divDown(totalSupply());

        _amountsOut[0] = _reserves[0].mulDown(_pctPool);
        _amountsOut[1] = _reserves[1].mulDown(_pctPool);

        _burnPoolTokens(_sender, _bptAmountIn);

        _downscaleDownArray(_amountsOut);

        _mutateAmounts(_reserves, _amountsOut, FixedPoint.sub);

        if (_protocolSwapFeePercentage != 0) {
            uint256 _bptFee = _determineBptFee(_reserves, _protocolSwapFeePercentage);
            // balancer fealty
            _mintPoolTokens(_protocolFeesCollector, _bptFee);
        }

        _cacheInvariantAndReserves(_reserves);

        return (_amountsOut, new uint256[](2));
    }

    function _determineBptFee(uint256[] memory _reserves, uint256 _protocolSwapFeePercentage)
        internal
        returns (uint256)
    {
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        // invariant growth from time only
        uint256 _currentAdjInvariant = _lastToken0Reserve.powDown(a) + _lastToken1Reserve.powDown(a);
        // actual current invariant
        uint256 _currentInvariant = _reserves[0].powDown(a) + _reserves[1].powDown(a);

        uint256 denom = _lastInvariant.mulDown(_currentAdjInvariant.divUp(_lastInvariant));
        return
            _currentInvariant.divDown(denom).sub(FixedPoint.ONE).mulDown(totalSupply()).mulDown(
                _protocolSwapFeePercentage
            );
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
            // add LP supply to Zero reserves as suggested by the yield space paper
            _reservesTokenIn += totalSupply();
            // remove all new underlying accured while the Target has been in this pool from Target reserve accounting,
            // then convert the remaining Target into underlying
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
            // _require(_request.amount <= balanceTokenIn.mulDown(_MAX_IN_RATIO), Errors.MAX_IN_RATIO);

            uint256 amountOut = _onSwapGivenIn(zeroIn, _request.amount, _reservesTokenIn, _reservesTokenOut);

            // amount out, so downscale down to avoid sending too much out by 1
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            _request.amount = _upscale(_request.amount, scalingFactorTokenOut);

            uint256 amountIn = _onSwapGivenOut(zeroIn, _request.amount, _reservesTokenIn, _reservesTokenOut);

            // amount in, so downscale up to ensure there's enough
            return _downscaleUp(amountIn, scalingFactorTokenIn);
        }
    }

    function _onSwapGivenIn(
        bool _zeroIn,
        uint256 _amountIn,
        uint256 _reservesTokenIn,
        uint256 _reservesTokenOut
    ) internal view returns (uint256) {
        // x_pre = token in reserves pre swap
        // y_pre = token out reserves pre swap

        // seconds until maturity
        // allow users to transfer using the constant sum pool after maturity
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;

        // `t` from the yield space paper (shifted based on issuance)
        uint256 t = ts.mulDown(ttm);

        // exponent from yield space paper (fees baked into `g`)
        uint256 a = (_zeroIn ? g2 : g1).mulUp(t).complement();

        // x1 = x_pre ^ (1 - t)
        uint256 x1 = _reservesTokenIn.powDown(a);

        // y1 = y_pre ^ (1 - t)
        uint256 y1 = _reservesTokenOut.powDown(a);

        // y2 = x_post ^ (1 - t)
        uint256 x2 = (_reservesTokenIn + _amountIn).powDown(a);

        // x1 + y1 = x2 + y_post ^ (1 - t)
        // -> y_post ^ (1 - t) = x1 + y1 - x2
        // -> y_post = (x1 + y1 - x2) ^ (1 / (1 - t))
        uint256 yPost = (x1 + y1 - x2).powDown(FixedPoint.ONE.divDown(a));
        require(_reservesTokenOut > yPost, "Too few reserves");

        // amount out = y_pre - y_post
        // amount out, so we're careful about rounding up and sending too many tokens
        return _reservesTokenOut.sub(yPost);
    }

    function _onSwapGivenOut(
        bool _zeroIn,
        uint256 _amountOut,
        uint256 _reservesTokenIn,
        uint256 _reservesTokenOut
    ) internal returns (uint256) {
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;

        uint256 t = ts.mulDown(ttm);
        uint256 a = (_zeroIn ? g2 : g1).mulUp(t).complement();
        uint256 x1 = _reservesTokenIn.powDown(a);
        uint256 y1 = _reservesTokenOut.powDown(a);
        uint256 y2 = (_reservesTokenOut - _amountOut).powDown(a);

        // need a require here, i think
        uint256 xPost = (x1 + y1 - y2).powDown(FixedPoint.ONE.divDown(a));
        // if x_post is more than initial reserves in, we don't have enough reserves to cover the swap
        require(xPost > _reservesTokenIn, "Too few reserves");

        return xPost.sub(_reservesTokenIn);
    }

    function _cacheInvariantAndReserves(uint256[] memory _reserves) internal {
        uint256 ttm = _maturity > block.timestamp ? uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;
        uint256 a = ts.mulDown(ttm).complement();

        _lastInvariant = _reserves[0].powDown(a) + _reserves[1].powDown(a);
        _lastToken0Reserve = _reserves[0];
        _lastToken1Reserve = _reserves[1];
    }

    // get token indices for Zero and Target
    function getIndices() public view returns (uint8 _zeroi, uint8 _targeti) {
        _zeroi = zeroi; // a regrettable SLOAD = 〰 =
        _targeti = _zeroi == 0 ? 1 : 0;
    }

    // scaling factors for Zero & Target tokens
    function _scalingFactor(bool zero) internal view returns (uint96) {
        return zero ? _scalingFactorZero : _scalingFactorTarget;
    }

    function _mutateAmounts(
        uint256[] memory toMutate,
        uint256[] memory arguments,
        function(uint256, uint256) pure returns (uint256) mutation
    ) private pure {
        toMutate[0] = mutation(toMutate[0], arguments[0]);
        toMutate[1] = mutation(toMutate[1], arguments[1]);
    }

    // scale number type to 18 decimals if need be
    function _upscale(uint256 amount, uint96 scalingFactor) internal pure returns (uint256) {
        return amount * scalingFactor;
    }

    // ensure number type is back to its base number of decimals (if less than 18)
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

    // Balancer's required interface
    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }

    function getVault() public view returns (IVault) {
        return _vault;
    }

    // Taken from balancer-v2-monorepo/**/WeightedPool2Tokens.sol
    modifier onlyVault(bytes32 poolId_) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId_ == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }
}
