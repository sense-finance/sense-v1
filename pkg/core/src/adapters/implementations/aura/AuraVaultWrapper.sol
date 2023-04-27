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
import "hardhat/console.sol";

interface IBalancerStablePreview {
    // ComposableStablePreview ImmutableData
    struct ImmutableData {
        address[] poolTokens;
        address[] rateProviders;
        uint256[] rawScalingFactors;
        bool[] isExemptFromYieldProtocolFee;
        address LP;
        bool noTokensExempt;
        bool allTokensExempt;
        uint256 bptIndex;
        uint256 totalTokens;
    }

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

interface IBooster {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);
}

interface IBaseRewardPool4626 {
    function pid() external view returns (uint256);
}

/// @title Aura Vault Wrapper
/// @notice Wraps an Aura vault to make it transferable. Its asset token (underlying) is the base token
/// of the Balancer pool.
/// @dev This contracts inherits ERC4626 but it does not implement all of it's function
contract AuraVaultWrapper is ERC4626, ExtractableReward {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    error BoosterDepositFailed();
    error NotImplemented();

    /* ========== IMMUTABLE PARAMS ========== */

    /// @notice The Aura vault contract
    ERC4626 public immutable aToken;
    uint256 public immutable auraPID;

    /// @notice pool data
    BalancerPool public immutable pool;
    bytes32 internal immutable poolId;
    address[] public rateProviders;
    uint256[] internal scalingFactors;
    bool[] internal exemptions = [false, false, false, false];
    IAsset[] internal poolAssets;
    IBalancerStablePreview public immutable previewHelper;

    /* ========== CONSTANTS ========== */

    IVault public constant balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBooster public constant auraBooster = IBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234); // Aura Booster
    uint256 public constant BPT_INDEX = 0;
    bool public constant NO_TOKENS_EXEMPT = true;
    bool public constant ALL_TOKENS_EXEMPT = false;

    constructor(
        ERC20 asset_,
        ERC4626 aToken_,
        IBalancerStablePreview previewHelper_
    ) ERC4626(asset_, _vaultName(aToken_), _vaultSymbol(aToken_)) ExtractableReward(msg.sender) {
        previewHelper = previewHelper_;
        aToken = aToken_;
        auraPID = IBaseRewardPool4626(address(aToken)).pid();

        // set pool data
        pool = BalancerPool(address(aToken.asset()));
        poolId = pool.getPoolId();
        (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);

        for (uint8 i; i < tokens.length; i++) {
            scalingFactors.push(10**tokens[i].decimals());
            tokens[i].safeApprove(address(balancerVault), type(uint256).max);
            poolAssets.push(IAsset(address(tokens[i])));
        }
        rateProviders = _convertRateProvidersToAddresses(pool.getRateProviders());

        // approve Aura Booster to pull LP
        ERC20(address(pool)).safeApprove(address(auraBooster), type(uint256).max);
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

    function beforeWithdraw(uint256, uint256 shares) internal virtual override {
        aToken.withdraw(shares, address(this), address(this));
        _redeemFromBalancer(shares);
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        // lock BPT into Aura Vault
        if (!auraBooster.deposit(auraPID, _depositToBalancer(assets), true)) revert BoosterDepositFailed();
    }

    function previewMint(uint256) public view virtual override returns (uint256) {
        revert NotImplemented();
    }

    function previewWithdraw(uint256) public view virtual override returns (uint256) {
        revert NotImplemented();
    }

    /* ========== Convenience Methods ========== */

    function depositFromBPT(uint256 bptIn, address receiver) external {
        ERC20(address(pool)).safeTransferFrom(msg.sender, address(this), bptIn);
        _mint(receiver, bptIn);
        if (!auraBooster.deposit(auraPID, bptIn, true)) revert BoosterDepositFailed(); // lock BPT into Aura Vault
        emit DepositFromBPT(msg.sender, receiver, bptIn);
    }

    function withdrawToBPT(
        uint256 shares,
        address receiver,
        address owner
    ) external {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        _burn(owner, shares);
        emit WithdrawToBPT(msg.sender, receiver, owner, shares);
        aToken.withdraw(shares, address(this), address(this));
        ERC20(address(pool)).safeTransfer(receiver, shares);
    }

    /* ========== ExtractableReward overrides ========== */

    function _isValid(address _token) internal virtual override returns (bool) {
        return true;
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
        uint256[] memory maxAmountsIn = new uint256[](poolAssets.length);
        uint256 index = find(poolAssets, address(asset)); // find index of underlying
        uint256 indexSkipBPT = index > _getBPTIndex() ? index - 1 : index;
        maxAmountsIn[index] = amountsIn[indexSkipBPT] = amt;

        // encode user data
        uint256 minBptOut = 0;
        bytes memory userData = abi.encode(IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minBptOut);

        request = IVault.JoinPoolRequest({
            assets: poolAssets,
            maxAmountsIn: maxAmountsIn,
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
        bytes memory userData = abi.encode(IVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, lpAmt, exitTokenIndex);

        request = IVault.ExitPoolRequest(poolAssets, minAmountsOut, userData, false);
    }

    /// @dev should be overriden if and only if BPT is one of the pool tokens
    function _getBPTIndex() internal view virtual returns (uint256) {
        return BPT_INDEX;
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
        IBalancerStablePreview.ImmutableData memory res;
        res.poolTokens = _convertIAssetsToAddresses(poolAssets);
        res.rateProviders = rateProviders;
        res.rawScalingFactors = scalingFactors;
        res.isExemptFromYieldProtocolFee = exemptions;
        res.LP = address(pool);
        res.noTokensExempt = NO_TOKENS_EXEMPT;
        res.allTokensExempt = ALL_TOKENS_EXEMPT;
        res.bptIndex = BPT_INDEX;
        res.totalTokens = res.poolTokens.length;

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

    /* ========== Events ========== */

    event DepositFromBPT(address indexed sender, address indexed receiver, uint256 indexed amount);
    event WithdrawToBPT(address indexed sender, address indexed receiver, address owner, uint256 indexed amount);
}
