// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { Crop } from "../../abstract/extensions/Crop.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";

interface WETHLike {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface CTokenLike {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);

    /// @notice Calculates the exchange rate from the underlying to the CToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() external view returns (uint256);

    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    /// The mint function transfers an asset into the protocol, which begins accumulating interest based
    /// on the current Supply Rate for the asset. The user receives a quantity of cTokens equal to the
    /// underlying tokens supplied, divided by the current Exchange Rate.
    /// @param mintAmount The amount of the asset to be supplied, in units of the underlying asset.
    /// @return 0 on success, otherwise an Error code
    function mint(uint256 mintAmount) external returns (uint256);

    /// The redeem function converts a specified quantity of cTokens into the underlying asset, and returns
    /// them to the user. The amount of underlying tokens received is equal to the quantity of cTokens redeemed,
    /// multiplied by the current Exchange Rate. The amount redeemed must be less than the user's Account Liquidity
    /// and the market's available liquidity.
    /// @param redeemTokens The number of cTokens to be redeemed.
    /// @return 0 on success, otherwise an Error code
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface CETHTokenLike {
    ///@notice Send Ether to CEther to mint
    function mint() external payable;
}

interface ComptrollerLike {
    /// @notice Claim all the comp accrued by holder in the specified markets
    /// @param holder The address to claim COMP for
    /// @param cTokens The list of markets to claim COMP in
    function claimComp(address holder, address[] memory cTokens) external;

    function markets(address target)
        external
        returns (
            bool isListed,
            uint256 collateralFactorMantissa,
            bool isComped
        );

    function oracle() external returns (address);
}

interface PriceOracleLike {
    /// @notice Get the price of an underlying asset.
    /// @param target The target asset to get the underlying price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function getUnderlyingPrice(address target) external view returns (uint256);

    function price(address underlying) external view returns (uint256);
}

/// @notice Adapter contract for cTokens
contract CAdapter is BaseAdapter, Crop, ExtractableReward {
    using SafeTransferLib for ERC20;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    bool public immutable isCETH;
    uint8 public immutable uDecimals;

    uint256 internal lastRewardedBlock;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    )
        Crop(_divider, _reward)
        BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams)
        ExtractableReward(_rewardsRecipient)
    {
        isCETH = _target == CETH;
        ERC20(_underlying).safeApprove(_target, type(uint256).max);
        uDecimals = CTokenLike(_underlying).decimals();
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
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

    function _claimReward() internal virtual override {
        // Avoid calling _claimReward more than once per block
        if (lastRewardedBlock != block.number) {
            lastRewardedBlock = block.number;
            address[] memory cTokens = new address[](1);
            cTokens[0] = target;
            ComptrollerLike(COMPTROLLER).claimComp(address(this), cTokens);
        }
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        price = isCETH ? 1e18 : PriceOracleLike(adapterParams.oracle).price(underlying);
    }

    function wrapUnderlying(uint256 uBal) external override returns (uint256 tBal) {
        ERC20 t = ERC20(target);

        ERC20(underlying).safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        if (isCETH) WETHLike(WETH).withdraw(uBal); // unwrap WETH into ETH

        // Mint target
        uint256 tBalBefore = t.balanceOf(address(this));
        if (isCETH) {
            CETHTokenLike(target).mint{ value: uBal }();
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
        uint256 uBalBefore = isCETH ? address(this).balance : u.balanceOf(address(this));
        if (CTokenLike(target).redeem(tBal) != 0) revert Errors.RedeemFailed();
        uint256 uBalAfter = isCETH ? address(this).balance : u.balanceOf(address(this));
        unchecked {
            uBal = uBalAfter - uBalBefore;
        }

        if (isCETH) {
            // Deposit ETH into WETH contract
            (bool success, ) = WETH.call{ value: uBal }("");
            if (!success) revert Errors.TransferFailed();
        }

        // Transfer underlying to sender
        ERC20(underlying).safeTransfer(msg.sender, uBal);
    }

    function _isValid(address _token) internal override returns (bool) {
        return (_token != target && _token != adapterParams.stake && _token != reward);
    }

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

    fallback() external payable {}
}
