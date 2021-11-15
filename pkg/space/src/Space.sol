// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";

import { IProtocolFeesCollector } from "@balancer-labs/v2-vault/contracts/interfaces/IProtocolFeesCollector.sol";
import { IMinimalSwapInfoPool } from "@balancer-labs/v2-vault/contracts/interfaces/IMinimalSwapInfoPool.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { IERC20 } from  "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";
import { Vault } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Errors, _require } from "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";

interface DividerLike {
    function series(address,uint48) external returns (address,address);
    function _acceptAdmin() external returns (uint256);
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

/// A Yield Space implementation extended such that it:
/// * allows LPs to deposit [Zero, wrapped yield-bearing underlying] rather than [Zero, underlying]
///   while keeping the standard yield space invariant accounting (ex: [Zero, cDAI] rather than [Zero, DAI])
/// * has an optional oracle
contract Space is 
    IMinimalSwapInfoPool, 
    BalancerPoolToken
{
    using FixedPoint for uint256;

    address public immutable divider;
    address public immutable adapter;
    uint8 public zeroi;

    address internal immutable _zero;
    address internal immutable _target;
    uint48 internal immutable _maturity;

    uint256 internal _initScale;
    bytes32 internal _poolId;
    bytes32 internal miscData;
    uint256 private lastInvariant;

    uint256 private constant _MINIMUM_BPT = 1e6;

    IERC20 public immutable _token0;
    uint96 internal immutable _scalingFactorZero;

    IERC20 public immutable _token1;
    uint96 internal immutable _scalingFactorTarget;

    IVault internal immutable _vault;
    IProtocolFeesCollector private immutable _protocolFeesCollector;
    
    uint256 public immutable ts;
    uint256 public immutable g1;
    uint256 public immutable g2;

    // event OracleEnabledChanged(bool enabled);

    constructor(
        IVault  vault_, 
        address _adapter, 
        uint48  maturity_, 
        address _divider,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) 
        BalancerPoolToken(AdapterLike(_adapter).name(), AdapterLike(_adapter).symbol())
    {
        bytes32 poolId = vault_.registerPool(IVault.PoolSpecialization.TWO_TOKEN);

        (address zero, ) = DividerLike(_divider).series(_adapter, maturity_);
        address target   = AdapterLike(_adapter).getTarget();

        IERC20[] memory tokens = new IERC20[](2);

        // ensure array of tokens is ordered correctly
        zeroi = zero < target ? 0 : 1;
        tokens[zeroi] = IERC20(zero);
        tokens[zeroi == 0 ? 1 : 0] = IERC20(target);
        vault_.registerTokens(poolId, tokens, new address[](2));

        // base balancer pool config
        _vault  = vault_;
        _poolId = poolId;
        _token0 = tokens[0];
        _token1 = tokens[1];
        _protocolFeesCollector = vault_.getProtocolFeesCollector();

        _scalingFactorZero   = uint96(10**(18 - ERC20(zero).decimals())  );
        _scalingFactorTarget = uint96(10**(18 - ERC20(target).decimals()));

        // general yield space config
        g1 = _g1;
        g2 = _g2;
        ts = _ts;

        _maturity = maturity_;

        // sense-specific slots
        divider = _divider;
        adapter = _adapter;
        _zero   = zero;
        _target = target;
    }

    function onJoinPool(
        bytes32 poolId_,
        address,
        address _recipient,
        uint256[] memory _currentBalances,
        uint256,
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(poolId_) returns (uint256[] memory, uint256[] memory) {
        (uint256[] memory _reqAmountsIn, uint256[] memory _dueProtocolFeeAmounts) = abi.decode(_userData, (uint256[], uint256[]));

        require(_maturity >= block.timestamp, "Can't join an already matured Pool");

        _upscaleArray(_reqAmountsIn);

        (uint8 _zeroi, uint8 _targeti) = getIndices();

        if (totalSupply() == 0) {
            // set the scale all future deposits will be backfilled to
            _initScale = AdapterLike(adapter).scale();

            // convert target balance to underlying
            // note: we can assume scale values will always be 18 decimals
            uint256 underlyingIn = _reqAmountsIn[_targeti] * _initScale / 1e18;
            // initial BPT minted is equal to the amount of underlying deposited
            uint256 bptAmountOut = underlyingIn - _MINIMUM_BPT;

            // just like weighted pool 2 token from the balancer v2 monorepo,
            // we lock _MINIMUM_BPT in by minting it for the zero address –
            // this reduces potential issues with rounding and ensures that this code path will only be traveled once
            _mintPoolTokens(address(0), _MINIMUM_BPT);
            _mintPoolTokens(_recipient, bptAmountOut);

            // for the first join, we don't pull any Zeros, regardless of what the caller requested –
            // this starts this pool off as "underlying" only, as speified in the yield space paper
            delete _reqAmountsIn[_zeroi];

            // amounts entering the Pool, so we round up
            _downscaleUpArray(_reqAmountsIn);

            return (_reqAmountsIn, new uint256[](2));
        } else {
            (uint256 bptToMint, uint256[] memory amountIn) = _determineMaxJoin(
                _reqAmountsIn, 
                _recipient, 
                _currentBalances
            );

            // bptToMint
            _mintPoolTokens(_recipient, bptToMint);

            // amounts entering the Pool, so we round up
            _downscaleUpArray(amountIn);

            // balancer piety
            // _mintPoolTokens(address(_protocolFeesCollector), bptToMint);

            // inspired by PR #990 in the balancer monorepo
            // always return zero dueProtocolFeeAmounts to the Vault - protocol fees are be paid in BPT,
            // by minting directly to the protocolFeeCollector
            return (amountIn, new uint256[](2));

        }
    }

    event A(uint);
    function _determineMaxJoin(
        uint256[] memory _reqAmountsIn, 
        address _recipient,
        uint256[] memory _currentBalances
    ) internal returns (uint256, uint256[] memory) {
        uint256 scale = AdapterLike(adapter).scale();
        uint[] memory amountsIn = new uint[](2);

        (uint8 _zeroi, uint8 _targeti) = getIndices();
        (uint256 _zeroReserves, uint256 _targetReserves) = (
            _currentBalances[_zeroi], _currentBalances[_targeti]
        );

        (uint256 _reqZerosIn, uint256 _reqTargetIn) = (
            _reqAmountsIn[_zeroi], _reqAmountsIn[_targeti]
        );

        // calculate the excess Target, remove it from the request, then convert the remaining Target into underlying
        uint256 _reqUnderlyingIn = (2 * _reqTargetIn - _reqTargetIn * scale / _initScale).mulDown(scale);

        // if we pulled all the requested underlying, what pct of the pool do we get?
        // current balance of Target will always be > 1 by the time this is called
        uint256 pctUnderlying = _reqUnderlyingIn.divDown(_targetReserves * _initScale / scale);

        // if the pool has been initialized, but there isn't yet any Target in it
        // we pull the all the offered Target and mint lp shares proportionally
        if (_zeroReserves == 0) { 
            uint256 bptToMint = totalSupply() * _reqUnderlyingIn / (_targetReserves * _initScale / scale);

            amountsIn[_targeti] = _reqTargetIn;
            amountsIn[_zeroi  ] = 0;
            return (bptToMint, amountsIn);
        } else {
            uint256 pctZeros = _reqZerosIn.divDown(_currentBalances[_zeroi]);

            // determine which amount in is our limiting factor
            if (pctUnderlying < pctZeros) {
                uint256 bptToMint = totalSupply() * pctUnderlying;

                amountsIn[_zeroi  ] = _zeroReserves * pctUnderlying;
                amountsIn[_targeti] = _reqTargetIn;
                return (bptToMint, amountsIn);
            } else {
                uint256 bptToMint = totalSupply() * pctZeros;

                amountsIn[_zeroi  ] = _reqZerosIn;
                amountsIn[_targeti] = _targetReserves * pctZeros;
                return (bptToMint, amountsIn);
            }
        }
    }

    function onExitPool(
        bytes32 poolId_,
        address,
        address _recipient,
        uint256[] memory _currentBalances,
        uint256,
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(poolId_)  returns (uint256[] memory, uint256[] memory) {
        (uint256[] memory _reqAmountsIn, uint256[] memory _dueProtocolFeeAmounts) = abi.decode(_userData, (uint256[], uint256[]));

        // uint256[] memory amountsIn = userData.initialAmountsIn();
        // InputHelpers.ensureInputLengthMatch(amountsIn.length, 2);

        // _upscaleArray(_reqAmountsIn);

        // (uint8 _zeroi, uint8 _targeti) = getIndices();

        // require (
        //     _realFYTokenCached == 0 || (
        //         uint256(_baseCached) * 1e18 / _realFYTokenCached >= minRatio &&
        //         uint256(_baseCached) * 1e18 / _realFYTokenCached <= maxRatio
        //     ),
        //     "Pool: Reserves ratio changed"
        // );

        // _burnPoolTokens(sender, bptAmountIn);

        return (new uint256[](2), new uint256[](2));

        //     // TODO: what happens if the target goes down from eg negative rates

        //     (uint256 bptToMint, uint256[] memory amountIn) = _determineAmountIn(
        //         _reqAmountsIn[_zeroi], 
        //         _reqAmountsIn[_targeti], 
        //         _recipient, 
        //         _currentBalances
        //     );

        //     return (amountIn, _dueProtocolFeeAmounts);
        // uint256 currentInvariant = WeightedMath._calculateInvariant(normalizedWeights, balances);
        // return
        //     WeightedMath._calcDueProtocolFeeBPTAmount(
        //         _lastInvariant,
        //         currentInvariant,
        //         totalSupply(),
        //         protocolSwapFeePercentage
        //     );

        // _mintPoolTokens(address(_protocolFeesCollector), bptToMint);
           // Since protocol fees are paid before the exit is processed, all calls to `totalSupply` in `_doExit` will
            // return the updated value, diluting current LPs.
        //     // _currentBalances[zeroi] = _currentBalances[zeroi] * _protocolSwapFeePercentage / _MIN_SWAP_FEE_PERCENTAGE;
        // }


        // // Both amountsOut and dueProtocolFeeAmounts are amounts exiting the Pool, so we round down.
        // _downscaleDownArray(amountsOut);
        // _downscaleDownArray(dueProtocolFeeAmounts);

        // // Update cached total supply and invariant using the results after the exit that will be used for future
        // // oracle updates, only if the pool was not paused (to minimize code paths taken while paused).
        // if (_isNotPaused()) {
        //     _cacheInvariantAndSupply();
    }

    function onSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    ) external override returns (uint256) {
        bool zeroIn = request.tokenIn == _token0;

        uint96 scalingFactorTokenIn  = _scalingFactor( zeroIn);
        uint96 scalingFactorTokenOut = _scalingFactor(!zeroIn);

        balanceTokenIn  = _upscale(balanceTokenIn,  scalingFactorTokenIn);
        balanceTokenOut = _upscale(balanceTokenOut, scalingFactorTokenOut);

        // Sense Adapter Scale value
        uint256 scale = AdapterLike(adapter).scale();

        // adjust Zero reserves with LP supply according to yield space paper
        // adjust Target reserves such that they're in backdated underlying terms
        if (zeroIn) {
            balanceTokenIn  += totalSupply();
            balanceTokenOut = (2 * balanceTokenOut - balanceTokenOut * scale / _initScale).mulDown(scale);
        } else {
            balanceTokenIn  = (2 * balanceTokenIn - balanceTokenIn * scale / _initScale).mulDown(scale);
            balanceTokenOut += totalSupply();
        }

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            request.amount = _upscale(request.amount, scalingFactorTokenIn);
            // _require(request.amount <= balanceTokenIn.mulDown(_MAX_IN_RATIO), Errors.MAX_IN_RATIO);

            uint256 amountOut = _onSwapGivenIn(
                zeroIn,
                request.amount,
                balanceTokenIn,
                balanceTokenOut
            );

            // amount out, so downscale down to avoid sending too much out by 1
            return _downscaleDown(amountOut, scalingFactorTokenOut);
        } else {
            request.amount = _upscale(request.amount, scalingFactorTokenOut);

            uint256 amountIn = _onSwapGivenOut(
                zeroIn,
                request.amount,
                balanceTokenIn,
                balanceTokenOut
            );

            // amount in, so downscale up to ensure there's enough
            return _downscaleUp(amountIn, scalingFactorTokenIn);
        }
    }

    function _onSwapGivenIn(
        bool _zeroIn,
        uint256 _amountIn,
        uint256 _reservesInAmount, 
        uint256 _reservesOutAmount
    ) internal view returns (uint256) {
        // x_pre = token in reserves pre swap
        // y_pre = token out reserves pre swap

        // seconds until maturity
        // allow users to transfer using the constant sum pool after maturity
        uint256 ttm = _maturity > block.timestamp ? 
            uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;

        // `t` from the yield space paper (shifted based on issuance)
        uint256 t = ts.mulDown(ttm);

        // exponent from yield space paper (fees baked into `g`)
        uint256 a = (_zeroIn ? g2 : g1).mulUp(t).complement();

        // x1 = x_pre ^ (1 - t)
        uint256 x1 = _reservesInAmount.powDown(a);

        // y1 = y_pre ^ (1 - t)
        uint256 y1 = _reservesOutAmount.powDown(a);

        // y2 = x_post ^ (1 - t)
        uint256 x2 = (_reservesInAmount + _amountIn).powDown(a);

        // x1 + y1 = x2 + y_post ^ (1 - t)
        // -> y_post ^ (1 - t) = x1 + y1 - x2
        // -> y_post = (x1 + y1 - x2) ^ (1 / (1 - t))
        uint256 yPost = (x1 + y1 - x2).powDown(FixedPoint.ONE.divDown(a)); 

        // amount out = y_pre - y_post
        // amount out, so we're careful about rounding and sending too many tokens
        return _reservesOutAmount - yPost;
    }

    function _onSwapGivenOut(
        bool _zeroIn,
        uint256 _amountOut,
        uint256 _reservesInAmount,
        uint256 _reservesOutAmount
    ) internal view returns (uint256) {
        // x_pre = token in reserves pre swap
        // y_pre = token out reserves pre swap

        // seconds until maturity
        // allow users to transfer using constant sum pool after maturity
        uint256 ttm = _maturity > block.timestamp ? 
            uint256(_maturity - block.timestamp) * FixedPoint.ONE : 0;

        // `t` from the yield space paper
        uint256 t = ts * ttm;

        // exponent from yield space paper (fees baked into `g`)
        uint256 a = FixedPoint.ONE - (_zeroIn ? g2 : g1).mulDown(t);

        // x1 = x_pre ^ (1 - t)
        uint256 x1 = _reservesInAmount.powDown(a);

        // y1 = y_pre ^ (1 - t)
        uint256 y1 = _reservesOutAmount.powDown(a);

        // y2 = x_post ^ (1 - t)
        uint256 y2 = (_reservesOutAmount - _amountOut).powDown(a);
        // emit A(x2);

        // x1 + y1 = x_post ^ (1 - t) + y2
        // -> x_post ^ (1 - t) = x1 + y1 - y2
        // -> x_post = (x1 + y1 - x2) ^ (1 / (1 - t))
        uint256 xPost = (x1 + y1 - y2).powDown(FixedPoint.ONE.divDown(a)); 

        // amount in = x_post - x_pre
        return xPost - _reservesInAmount;
    }


    // get the token indices for Zero and Target
    function getIndices() public view returns (uint8 _zeroi, uint8 _targeti) {
        _zeroi   = zeroi; // a regrettable SLOAD
        _targeti = _zeroi == 0 ? 1 : 0;
    }

    // scaling factors for Zero & Target tokens
    function _scalingFactor(bool zero) internal view returns (uint96) {
        return zero ? _scalingFactorZero : _scalingFactorTarget;
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
        amounts[_zeroi  ] = amounts[_zeroi  ] * _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] * _scalingFactor(false);
    }
    function _downscaleDownArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi  ] = amounts[_zeroi  ] / _scalingFactor(true);
        amounts[_targeti] = amounts[_targeti] / _scalingFactor(false);
    }
    function _downscaleUpArray(uint256[] memory amounts) internal view {
        (uint8 _zeroi, uint8 _targeti) = getIndices();
        amounts[_zeroi  ] = 1 + (amounts[_zeroi  ] - 1) / _scalingFactor(true);
        amounts[_targeti] = 1 + (amounts[_targeti] - 1) / _scalingFactor(false);
    }

    // balancer pool requirements
    function getPoolId() public view override returns (bytes32) {
        return _poolId;
    }
    function getVault() public view returns (IVault) {
        return _vault;
    }

    // modifiers
     modifier onlyVault(bytes32 poolId_) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(poolId_    == getPoolId(),         Errors.INVALID_POOL_ID);
        _;
    }
}