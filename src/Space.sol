// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// External references
import { BalancerPoolToken } from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { IMinimalSwapInfoPool } from "@balancer-labs/v2-vault/contracts/interfaces/IMinimalSwapInfoPool.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { IERC20 } from  "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";
import { ERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/ERC20.sol";
import { Errors, _require } from "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";
import { LogCompression } from "@balancer-labs/v2-solidity-utils/contracts/helpers/LogCompression.sol";
import { BasePoolAuthorization, IAuthorizer } from "@balancer-labs/v2-pool-utils/contracts/BasePoolAuthorization.sol";
import { Authentication } from "@balancer-labs/v2-solidity-utils/contracts/helpers/Authentication.sol";
import { WeightedPool2TokensMiscData } from "@balancer-labs/v2-pool-weighted/contracts/WeightedPool2TokensMiscData.sol";

interface DividerLike {
    function series(
        address feed,
        uint256 maturity
    ) external returns (address,address);
    function _acceptAdmin() external returns (uint256);
}

interface FeedLike {
    function underlying() external returns (address);
    function scale() external returns (uint256);
}


contract Feed {
    function underlying() external returns (address) {
        return address(0);
    }

    function scale() external returns (uint256) {
        return 1e18;
    }
}

contract Divider {
    function series(
        address feed,
        uint256 maturity
    ) external returns (address,address) {
        return (address(1), address(2));
    }
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

contract YS is 
    IMinimalSwapInfoPool, 
    BalancerPoolToken,
    BasePoolAuthorization
{
    using FixedPoint for uint256;
    using WeightedPool2TokensMiscData for bytes32;

    uint256 internal immutable _scalingFactor0;
    uint256 internal immutable _scalingFactor1;

    IVault private immutable vault;
    address public immutable divider;
    address public immutable feed;
    address internal immutable zero;
    address internal immutable underlying;

    IERC20 internal immutable _token0;
    IERC20 internal immutable _token1;

    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 1e17; // 10%

    bytes32 internal miscData;
    uint256 private lastInvariant;

    bytes32 private poolId;
    uint256 public zeroReserves;
    uint256 public underlyingReserves;
    uint256 public timeShift;

    uint256 public g1;
    uint256 public g2;

    event OracleEnabledChanged(bool enabled);
    event SwapFeePercentageChanged(uint256 swapFeePercentage);

    // struct NewPoolParams {
    //     IVault vault;
    //     string name;
    //     string symbol;
    //     IERC20 token0;
    //     IERC20 token1;
    //     uint256 normalizedWeight0;
    //     uint256 normalizedWeight1;
    //     uint256 swapFeePercentage;
    //     uint256 pauseWindowDuration;
    //     uint256 bufferPeriodDuration;
    //     bool oracleEnabled;
    //     address owner;
    // }

    constructor(
        IVault _vault, 
        address _feed, 
        uint256 _maturity, 
        address _divider,
        uint256 _timeShift,
        uint256 _g1,
        uint256 _g2
    ) 
        Authentication(bytes32(uint256(msg.sender)))
        BalancerPoolToken("name", "symbol")
        BasePoolAuthorization(msg.sender)
    {
        poolId = _vault.registerPool(IVault.PoolSpecialization.TWO_TOKEN);
        vault = _vault;
        
        (address _zero,   ) = DividerLike(_divider).series(_feed, _maturity);
        address _underlying = FeedLike(_feed).underlying();

        // FeedLike(feed).scale()

        IERC20[] memory tokens = new IERC20[](2);
        (uint256 z, uint256 u) = _zero < _underlying ? (0, 1) : (1, 0);
        tokens[z] = IERC20(_zero);
        tokens[u] = IERC20(_underlying);

        _vault.registerTokens(poolId, tokens, new address[](2));

        _token0 = tokens[0];
        _token1 = tokens[1];

        _scalingFactor0 = _computeScalingFactor(tokens[0]);
        _scalingFactor1 = _computeScalingFactor(tokens[1]);

        divider = _divider;
        feed    = _feed;
        zero    = _zero;
        underlying = _underlying;

        timeShift = _timeShift;
        g1 = _g1;
        g2 = _g2;
    }


    function onJoinPool(
        bytes32 _poolId,
        address _sender,
        address _recipient,
        uint256[] memory _currentBalances,
        uint256 _lastChangeBlock,
        uint256 _protocolSwapFeePercentage,
        bytes memory _userData
    ) external override onlyVault(_poolId) returns (uint256[] memory, uint256[] memory) {
        (uint256[] memory amountsIn, uint256[] memory dueProtocolFeeAmounts) = abi.decode(_userData, (uint256[], uint256[]));
    }

    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory currentBalances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external override returns (uint256[] memory, uint256[] memory) {
        (uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts) = abi.decode(userData, (uint256[], uint256[]));
    }

    uint256 private _multiplier = FixedPoint.ONE;

    function setMultiplier(uint256 newMultiplier) external {
        _multiplier = newMultiplier;
    }

    function onSwap(
        SwapRequest memory request,
        uint256 balanceTokenIn,
        uint256 balanceTokenOut
    ) external view override returns (uint256) {
        bool tokenInIsToken0 = request.tokenIn == _token0;

        uint256 scalingFactorTokenIn  = _scalingFactor(tokenInIsToken0);
        uint256 scalingFactorTokenOut = _scalingFactor(!tokenInIsToken0);

        balanceTokenIn  = _upscale(balanceTokenIn, scalingFactorTokenIn);
        balanceTokenOut = _upscale(balanceTokenOut, scalingFactorTokenOut);

        // _updateOracle(
        //     request.lastChangeBlock,
        //     tokenInIsToken0 ? balanceTokenIn : balanceTokenOut,
        //     tokenInIsToken0 ? balanceTokenOut : balanceTokenIn
        // );

        if (request.kind == IVault.SwapKind.GIVEN_IN) {
            // Fees are subtracted before scaling, to reduce the complexity of the rounding direction analysis.
            // This is amount - fee amount, so we round up (favoring a higher fee amount).
            uint256 feeAmount = request.amount.mulUp(getSwapFeePercentage());
            request.amount = _upscale(request.amount.sub(feeAmount), scalingFactorTokenIn);

            // uint256 amountOut = _onSwapGivenIn(
            //     request,
            //     balanceTokenIn,
            //     balanceTokenOut,
            //     normalizedWeightIn,
            //     normalizedWeightOut
            // );

            // amountOut tokens are exiting the Pool, so we round down.
            // return _downscaleDown(amountOut, scalingFactorTokenOut);
            return 0;
        } else {

        }
    }

    // function _onSwapGivenIn(
    //     SwapRequest memory swapRequest,
    //     uint256 currentBalanceTokenIn,
    //     uint256 currentBalanceTokenOut,
    //     uint256 normalizedWeightIn,
    //     uint256 normalizedWeightOut
    // ) private pure returns (uint256) {
    //     // Swaps are disabled while the contract is paused.
    //     return
    //         WeightedMath._calcOutGivenIn(
    //             currentBalanceTokenIn,
    //             normalizedWeightIn,
    //             currentBalanceTokenOut,
    //             normalizedWeightOut,
    //             swapRequest.amount
    //         );
    // }



    // TODO: too much out/ eat up all the reserves?

    /// @notice Returns the amount of underlying the caller will be able to swap out for some balance of Zero in
    /// @param zerosIn Balance of Zero to swap in
    /// @param maturity Maturity date for the Series
    function zeroIn(uint256 zerosIn, uint256 maturity) public view returns (uint256 underlyingOut /* 18 decimals */) {
        // x_pre = underlying reserves pre swap
        // y_pre = Zero reserves pre swap

        // seconds until maturity
        uint256 ttm = maturity - block.timestamp;

        // `t` from the yield space paper (shifted based on issuance)
        uint256 t = timeShift * ttm;

        // exponent from yield space paper (with a fee factored in)
        uint256 a = FixedPoint.ONE - g1.mulUp(t);

        // x1 = x_pre ^ (1 - t)
        uint256 x1 = underlyingReserves.powDown(a);

        // y1 = y_pre ^ (1 - t)
        uint256 y1 = zeroReserves.powDown(a);

        // y2 = y_post ^ (1 - t)
        uint256 y2 = (zeroReserves + zerosIn).powDown(a);

        // x1 + y1 = x_post ^ (1 - t) + y2
        // -> x_post ^ (1 - t) = x1 + y1 - y2
        // -> x_post = (x1 + y1 - y2) ^ (1 / (1 - t))
        uint256 xPost = (x1 + y1 - y2).powDown(FixedPoint.ONE.divDown(a)); 

        // x_out = x_pre - x_post
        underlyingOut = underlyingReserves - xPost;
    }

    function underlyingIn() external returns (uint256 zeroOut /* 18 decimals */) {

    }

    function getSwapFeePercentage() public view returns (uint256) {
        return miscData.swapFeePercentage();
    }

    // Caller must be approved by the Vault's Authorizer
    function setSwapFeePercentage(uint256 swapFeePercentage) public virtual authenticate {
        _setSwapFeePercentage(swapFeePercentage);
    }

    function _setSwapFeePercentage(uint256 swapFeePercentage) private {
        _require(swapFeePercentage >= _MIN_SWAP_FEE_PERCENTAGE, Errors.MIN_SWAP_FEE_PERCENTAGE);
        _require(swapFeePercentage <= _MAX_SWAP_FEE_PERCENTAGE, Errors.MAX_SWAP_FEE_PERCENTAGE);

        miscData = miscData.setSwapFeePercentage(swapFeePercentage);
        emit SwapFeePercentageChanged(swapFeePercentage);
    }

    function _getAuthorizer() internal view override returns (IAuthorizer) {
        // Access control management is delegated to the Vault's Authorizer. This lets Balancer Governance manage which
        // accounts can call permissioned functions: for example, to perform emergency pauses.
        // If the owner is delegated, then *all* permissioned functions, including `setSwapFeePercentage`, will be under
        // Governance control.
        return getVault().getAuthorizer();
    }

    function _isOwnerOnlyAction(bytes32 actionId) internal view virtual override returns (bool) {
        return false;
    }

    function _scalingFactor(bool token0) internal view returns (uint256) {
        return token0 ? _scalingFactor0 : _scalingFactor1;
    }

    function _upscale(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount * scalingFactor;
    }

    function _upscaleArray(uint256[] memory amounts) internal view {
        amounts[0] = amounts[0] * _scalingFactor(true );
        amounts[1] = amounts[1] * _scalingFactor(false);
    }

    function _downscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    function _downscaleDownArray(uint256[] memory amounts) internal view {
        amounts[0] = FixedPoint.divDown(amounts[0], _scalingFactor(true));
        amounts[1] = FixedPoint.divDown(amounts[1], _scalingFactor(false));
    }

    function _downscaleUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divUp(amount, scalingFactor);
    }

    function _downscaleUpArray(uint256[] memory amounts) internal view {
        amounts[0] = FixedPoint.divUp(amounts[0], _scalingFactor(true));
        amounts[1] = FixedPoint.divUp(amounts[1], _scalingFactor(false));
    }

    function _computeScalingFactor(IERC20 token) private view returns (uint256) {
        // Tokens with more than 18 decimals are not supported
        uint256 decimalsDifference = 18 - ERC20(address(token)).decimals();
        return 10**decimalsDifference;
    }

    function getPoolId() public view override returns (bytes32) {
        return poolId;
    }

    function getVault() public view returns (IVault) {
        return vault;
    }

     modifier onlyVault(bytes32 _poolId) {
        _require(msg.sender == address(getVault()), Errors.CALLER_NOT_VAULT);
        _require(_poolId == getPoolId(), Errors.INVALID_POOL_ID);
        _;
    }

}