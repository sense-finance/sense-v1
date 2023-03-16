// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
// import { IVault } from "./IVault.sol";
import { BalancerPool } from "../../../external/balancer/Pool.sol";
import { BalancerVault as IVault, IAsset } from "../../../external/balancer/Vault.sol";
import { RateProvider } from "../../../external/balancer/RateProvider.sol";

interface IBalancerStablePreview {
    function joinPoolPreview(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request,
        bytes memory data
    ) external view returns (uint256 amountBptOut);

    function exitPoolPreview(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.ExitPoolRequest memory request,
        bytes memory data
    ) external view returns (uint256 amountTokenOut);
}

/// @title Aura Vault Wrapper
/// @notice Wraps an Aura vault to make it transferable. Its asset token (underlying) is the base token
/// of the Balancer pool.
/// @dev This contracts inherits ERC4626 but it does not implement all of it's function
contract AuraVaultWrapper is ERC4626, ExtractableReward {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    struct ImmutableData {
        address LP;
        address[] poolTokens;
        address[] rateProviders;
        uint256[] rawScalingFactors;
    }

    /* ========== IMMUTABLE PARAMS ========== */

    /// @notice The Aura vault contract
    ERC4626 public immutable aToken;

    /// @notice pool data
    BalancerPool public immutable pool;
    bytes32 internal immutable poolId;
    address[] internal rateProviders;
    uint256[] internal scalingFactors;
    IAsset[] internal poolAssets;

    /* ========== CONSTANTS ========== */

    // Helper from Pendle Finance to preview Balancer joins/exits
    IBalancerStablePreview internal constant previewHelper =
        IBalancerStablePreview(0x21a9fd7212F37c35B030e9374510F99128d59CD3);
    IVault public constant balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // TODO: check if we need it
    // uint256 internal constant AURA_PID = 15;
    // address internal constant LP = 0x1E19CF2D73a72Ef1332C882F20534B6519Be0276;

    constructor(ERC20 asset_, ERC4626 aToken_)
        ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_))
        ExtractableReward(msg.sender)
    {
        aToken = aToken_;

        // set pool data
        pool = BalancerPool(address(aToken.asset()));
        (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(pool.getPoolId());
        poolId = pool.getPoolId();

        for (uint8 i; i < tokens.length; i++) {
            scalingFactors.push(10**tokens[i].decimals());
            tokens[i].safeApprove(address(balancerVault), type(uint256).max);
        }
        poolAssets = _convertERC20sToAssets(tokens);
        rateProviders = _convertRateProvidersToAddresses(pool.getRateProviders());
    }

    /* ========== ERC4626 overrides ========== */

    function totalAssets() public view virtual override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        IVault.JoinPoolRequest memory request = _assembleJoinRequest(assets);
        return previewHelper.joinPoolPreview(poolId, address(this), address(this), request, _getImmutablePoolData());
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        IVault.ExitPoolRequest memory request = _assembleExitRequest(shares);

        assets = previewHelper.exitPoolPreview(poolId, address(this), address(this), request, _getImmutablePoolData());
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override {
        aToken.withdraw(shares, address(this), address(this));
        // TODO: check diff with:
        // IRewards(auraRewardManager).withdrawAndUnwrap(amountSharesToRedeem, false);
        _redeemFromBalancer(shares);
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        uint256 bptOut = _depositToBalancer(assets);

        // lock BPT into Aura Vault
        ERC20(address(pool)).safeApprove(address(aToken), assets); // approve Aura vault to pull BPT
        aToken.deposit(bptOut, address(this)); // TODO: check if I should do this or rather what Pendle does -> calls booster.deposit()
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        revert("NOT IMPLEMENTED");
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        revert("NOT IMPLEMENTED");
    }

    /* ========== ExtractableReward overrides ========== */

    function _isValid(address _token) internal virtual override returns (bool) {
        return (_token != address(aToken)); // TODO: aToken is anyways non-transferable, maybe this check is not needed?
    }

    /* ========== ERC20 metadata generation ========== */

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("Wrapped ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("w-", asset_.symbol());
    }

    /* ========== Helpers ========== */

    function _depositToBalancer(uint256 amt) internal virtual returns (uint256 bptOut) {
        IVault.JoinPoolRequest memory request = _assembleJoinRequest(amt);
        balancerVault.joinPool(poolId, address(this), address(this), request);
        bptOut = ERC20(address(pool)).balanceOf(address(this));
    }

    function _assembleJoinRequest(uint256 amt) internal view virtual returns (IVault.JoinPoolRequest memory request) {
        // max amounts in
        uint256 amountsLength = _getBPTIndex() < type(uint256).max ? poolAssets.length - 1 : poolAssets.length;

        uint256[] memory amountsIn = new uint256[](amountsLength);
        uint256 index = find(poolAssets, address(asset)); // find index of underlying
        // uint256 indexSkipBPT = index > _getBPTIndex() ? index - 1 : index;
        amountsIn[index] = amt;

        // encode user data
        uint256 minBptOut = 0; // TODO: fine to be 0?
        // 1 = EXACT_TOKENS_IN_FOR_BPT_OUT
        bytes memory userData = abi.encode(1, amountsIn, minBptOut);

        request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });
    }

    function _redeemFromBalancer(uint256 lpAmt) internal virtual returns (uint256) {
        uint256 balanceBefore = asset.balanceOf(address(this));

        IVault.ExitPoolRequest memory request = _assembleExitRequest(lpAmt);
        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);

        // calculate amount of tokens out
        uint256 balanceAfter = asset.balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    function _assembleExitRequest(uint256 lpAmt) internal view virtual returns (IVault.ExitPoolRequest memory request) {
        uint256[] memory minAmountsOut = new uint256[](poolAssets.length);

        // encode user data
        uint256 exitTokenIndex = find(poolAssets, address(asset));

        // must drop BPT index as well
        exitTokenIndex = _getBPTIndex() < exitTokenIndex ? exitTokenIndex - 1 : exitTokenIndex;
        // 0 = EXACT_BPT_IN_FOR_ONE_TOKEN_OUT
        bytes memory userData = abi.encode(0, lpAmt, exitTokenIndex);

        request = IVault.ExitPoolRequest(poolAssets, minAmountsOut, userData, false);
    }

    /// @dev should be overriden if and only if BPT is one of the pool tokens
    function _getBPTIndex() internal view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @notice return index of the element if found, else return uint256.max
    function find(IAsset[] memory array, address element) internal pure returns (uint256 index) {
        uint256 length = array.length;
        for (uint256 i = 0; i < length; ) {
            if (address(array[i]) == element) return i;
            unchecked {
                i++;
            }
        }
        return type(uint256).max;
    }

    function _getImmutablePoolData() internal view virtual returns (bytes memory) {
        ImmutableData memory res;
        res.LP = address(pool);
        res.poolTokens = _convertIAssetsToAddresses(poolAssets);
        res.rateProviders = rateProviders;
        res.rawScalingFactors = scalingFactors;

        return abi.encode(res);
    }

    function _convertIAssetsToAddresses(IAsset[] memory assets) internal pure returns (address[] memory addresses) {
        assembly {
            addresses := assets
        }
    }

    function _convertRateProvidersToAddresses(RateProvider[] memory providers)
        internal
        pure
        returns (address[] memory addresses)
    {
        assembly {
            addresses := providers
        }
    }

    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }
}
