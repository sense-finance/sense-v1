// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Crops } from "../../abstract/extensions/Crops.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { CTokenLike } from "../compound/CAdapter.sol";

interface WETHLike {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface FETHTokenLike {
    ///@notice Send Ether to CEther to mint
    function mint() external payable;
}

interface FTokenLike {
    function isCEther() external view returns (bool);
}

interface FComptrollerLike {
    function markets(address target) external returns (bool isListed, uint256 collateralFactorMantissa);

    function oracle() external returns (address);

    function getRewardsDistributors() external view returns (address[] memory);
}

interface RewardsDistributorLike {
    ///
    /// @notice Claim all the rewards accrued by holder in the specified markets
    /// @param holder The address to claim rewards for
    ///
    function claimRewards(address holder) external;

    function marketState(address marker) external view returns (uint224 index, uint32 lastUpdatedTimestamp);

    function rewardToken() external view returns (address rewardToken);
}

interface PriceOracleLike {
    /// @notice Get the price of an underlying asset.
    /// @param target The target asset to get the underlying price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function getUnderlyingPrice(address target) external view returns (uint256);

    function price(address underlying) external view returns (uint256);
}

/// @notice Adapter contract for fTokens
contract FAdapter is BaseAdapter, Crops, ExtractableReward {
    using SafeTransferLib for ERC20;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant FETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    mapping(address => address) public rewardsDistributorsList; // rewards distributors for reward token

    address public immutable comptroller;
    bool public immutable isFETH;
    uint8 public immutable uDecimals;

    uint256 internal lastRewardedBlock;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        address _comptroller,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens,
        address[] memory _rewardsDistributorsList
    )
        Crops(_divider, _rewardTokens)
        BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams)
        ExtractableReward(_rewardsRecipient)
    {
        rewardTokens = _rewardTokens;
        comptroller = _comptroller;
        isFETH = FTokenLike(_target).isCEther();

        ERC20(_underlying).safeApprove(_target, type(uint256).max);
        uDecimals = CTokenLike(_underlying).decimals();

        // Initialize rewardsDistributorsList mapping
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardsDistributorsList[_rewardTokens[i]] = _rewardsDistributorsList[i];
        }
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
    }

    /// @return Exchange rate from Target to Underlying using Compound's `exchangeRateCurrent()`, normed to 18 decimals
    function scale() external override returns (uint256) {
        uint256 exRate = CTokenLike(target).exchangeRateCurrent();
        return _to18Decimals(exRate);
    }

    function scaleStored() external view override returns (uint256) {
        uint256 exRate = CTokenLike(target).exchangeRateStored();
        return _to18Decimals(exRate);
    }

    function _claimRewards() internal virtual override {
        // Avoid calling _claimRewards more than once per block
        if (lastRewardedBlock != block.number) {
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                if (rewardTokens[i] != address(0))
                    RewardsDistributorLike(rewardsDistributorsList[rewardTokens[i]]).claimRewards(address(this));
            }
        }
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        price = isFETH ? 1e18 : PriceOracleLike(adapterParams.oracle).price(underlying);
    }

    function wrapUnderlying(uint256 uBal) external override returns (uint256 tBal) {
        ERC20 t = ERC20(target);

        ERC20(underlying).safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        if (isFETH) WETHLike(WETH).withdraw(uBal); // unwrap WETH into ETH

        // Mint target
        uint256 tBalBefore = t.balanceOf(address(this));
        if (isFETH) {
            FETHTokenLike(target).mint{ value: uBal }();
        } else {
            if (CTokenLike(target).mint(uBal) != 0) revert Errors.MintFailed();
        }
        uint256 tBalAfter = t.balanceOf(address(this));

        // Transfer target to sender
        t.safeTransfer(msg.sender, tBal = tBalAfter - tBalBefore);
    }

    function unwrapTarget(uint256 tBal) external override returns (uint256 uBal) {
        ERC20 u = ERC20(underlying);
        ERC20(target).safeTransferFrom(msg.sender, address(this), tBal); // pull target

        // Redeem target for underlying
        uint256 uBalBefore = isFETH ? address(this).balance : u.balanceOf(address(this));
        if (CTokenLike(target).redeem(tBal) != 0) revert Errors.RedeemFailed();
        uint256 uBalAfter = isFETH ? address(this).balance : u.balanceOf(address(this));
        unchecked {
            uBal = uBalAfter - uBalBefore;
        }

        if (isFETH) {
            // Deposit ETH into WETH contract
            (bool success, ) = WETH.call{ value: uBal }("");
            if (!success) revert Errors.TransferFailed();
        }

        // Transfer underlying to sender
        ERC20(underlying).safeTransfer(msg.sender, uBal);
    }

    function _isValid(address _token) internal override returns (bool) {
        for (uint256 i = 0; i < rewardTokens.length; ) {
            if (_token == rewardTokens[i]) return false;
            unchecked {
                ++i;
            }
        }

        // Check that token is neither the target nor the stake
        return (_token != target && _token != adapterParams.stake);
    }

    /* ========== ADMIN ========== */

    /// @notice Overrides both the rewardTokens and the rewardsDistributorsList arrays.
    /// @param _rewardTokens New reward tokens array
    /// @param _rewardsDistributorsList New rewards distributors list array
    function setRewardTokens(address[] memory _rewardTokens, address[] memory _rewardsDistributorsList)
        public
        virtual
        requiresTrust
    {
        super.setRewardTokens(_rewardTokens);
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            rewardsDistributorsList[_rewardTokens[i]] = _rewardsDistributorsList[i];
        }
        emit RewardsDistributorsChanged(_rewardsDistributorsList);
    }

    /* ========== INTERNAL UTILS ========== */

    function _to18Decimals(uint256 exRate) internal view returns (uint256) {
        // From the Compound docs:
        // "exchangeRateCurrent() returns the exchange rate, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals)"
        //
        // The equation to norm an asset to 18 decimals is:
        // `num * 10**(18 - decimals)`
        //
        // So, when we try to norm exRate to 18 decimals, we get the following:
        // `exRate * 10**(18 - exRateDecimals)`
        // -> `exRate * 10**(18 - (18 - 8 + uDecimals))`
        // -> `exRate * 10**(8 - uDecimals)`
        // -> `exRate / 10**(uDecimals - 8)`
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    /* ========== LOGS ========== */

    event RewardsDistributorsChanged(address[] indexed rewardsDistributorsList);

    /* ========== FALLBACK ========== */

    fallback() external payable {}
}
