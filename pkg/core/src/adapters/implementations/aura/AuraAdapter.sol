// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { RateProvider } from "../../../external/balancer/RateProvider.sol";

// Internal references
import { AuraVaultWrapper } from "./AuraVaultWrapper.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { Crops } from "../../abstract/extensions/Crops.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import "hardhat/console.sol";

interface PriceOracleLike {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IRewards {
    function getReward() external returns (bool);

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 _idx) external returns (address);
}

/// @notice Adapter contract for Aura Vaults (aToken)
contract AuraAdapter is BaseAdapter, Crops, ExtractableReward {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    /// @notice Cached scale value from the last call to `scale()`
    uint256 public override scaleStored;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    )
        BaseAdapter(_divider, _target, address(AuraVaultWrapper(_target).asset()), _ifee, _adapterParams)
        Crops(_divider, _rewardTokens)
        ExtractableReward(_rewardsRecipient)
    {
        // approve target (wrapper) to pull WETH (used on wrapUnderlying())
        ERC20(underlying).approve(target, type(uint256).max);
        // set an inital cached scale value
        scaleStored = _getRate();
    }

    /// @return exRate Eth per wstEtH (natively in 18 decimals)
    function scale() external virtual override returns (uint256 exRate) {
        exRate = _getRate();

        // update value only if different than the previous
        if (exRate != scaleStored) scaleStored = exRate;
    }

    function getUnderlyingPrice() external view override returns (uint256 rethPrice) {
        rethPrice = RateProvider(AuraVaultWrapper(target).rateProviders(3)).getRate(); // RETH is the 4th rate provider
    }

    function unwrapTarget(uint256 amount) external override returns (uint256 assets) {
        ERC20(target).safeTransferFrom(msg.sender, address(this), amount); // pull w-auraB-rETH-STABLE-vault
        assets = AuraVaultWrapper(target).redeem(amount, msg.sender, address(this));
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256 aToken) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), amount); // pull WETH
        aToken = AuraVaultWrapper(target).deposit(amount, msg.sender);
    }

    function _isValid(address _token) internal override returns (bool) {
        return (_token != target && _token != adapterParams.stake);
    }

    /* ========== Crops overrides ========== */

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
    }

    function _claimRewards() internal override {
        address aToken = address(AuraVaultWrapper(target).aToken());
        uint256 extraRewardsLen = IRewards(aToken).extraRewardsLength();
        if (extraRewardsLen == 0) {
            IRewards(aToken).getReward(address(target), false);
        } else {
            // get also rewards from linked rewards
            IRewards(aToken).getReward(address(target), true);

            // extract extra rewards from target
            for (uint256 i = 0; i < extraRewardsLen; i++) {
                ExtractableReward(target).extractToken(IRewards(aToken).extraRewards(i));
            }
        }

        // extract rewardTokens (BAL & AURA) from wrapper
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            ExtractableReward(target).extractToken(rewardTokens[i]);
        }
    }

    /* ========== Utils ========== */

    function _getRate() internal returns (uint256) {
        return RateProvider(address(AuraVaultWrapper(target).pool())).getRate();
    }
}
