// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { CropAdapter } from "../CropAdapter.sol";

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);

    function decimals() external returns (uint256);

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

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

interface PriceOracleInterface {
    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function price(address underlying) external view returns (uint256);
}

/// @notice Adapter contract for cTokens
contract CAdapter is CropAdapter {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    function initialize(
        address _divider,
        AdapterParams memory _adapterParams,
        address _reward
    ) public virtual override initializer {
        // approve underlying contract to pull target (used on wrapUnderlying())
        ERC20 u = ERC20(CTokenInterface(_adapterParams.target).underlying());
        u.safeApprove(_adapterParams.target, type(uint256).max);
        super.initialize(_divider, _adapterParams);
    }

    /// @return Exchange rate from Target to Underlying using Compound's `exchangeRateCurrent()`, normed to 18 decimals
    function _scale() internal override returns (uint256) {
        uint256 uDecimals = CTokenInterface(underlying()).decimals();
        uint256 exRate = CTokenInterface(adapterParams.target).exchangeRateCurrent();
        // From the Compound docs:
        // "exchangeRateCurrent() returns the exchange rate, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals)"
        //
        // And the normal equation to norm an asset to 18 decimals is:
        // `num * 10**(18 - decimals)`
        //
        // So, when we try to norm exRate to 18 decimals, we get the following:
        // `exRate * 10**(18 - exRateDecimals)` 
        // -> `exRate * 10**(18 - (18 - 8 + uDecimals))` 
        // -> `exRate * 10**(8 - uDecimals)`
        // -> `exRate / 10**(uDecimals - 8)`
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }

    function underlying() external view override returns (address) {
        return CTokenInterface(adapterParams.target).underlying();
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return PriceOracleInterface(adapterParams.oracle).price(CTokenInterface(adapterParams.target).underlying());
    }

    function wrapUnderlying(uint256 uBal) external override returns (uint256) {
        ERC20 u = ERC20(CTokenInterface(adapterParams.target).underlying());
        ERC20 target = ERC20(adapterParams.target);
        u.safeTransferFrom(msg.sender, address(this), uBal); // pull underlying

        // mint target
        uint256 tBalBefore = target.balanceOf(address(this));
        require(CTokenInterface(adapterParams.target).mint(uBal) == 0, "Mint failed");
        uint256 tBalAfter = target.balanceOf(address(this));
        uint256 tBal = tBalAfter - tBalBefore;

        // transfer target to sender
        ERC20(target).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    function unwrapTarget(uint256 tBal) external override returns (uint256) {
        ERC20 u = ERC20(CTokenInterface(adapterParams.target).underlying());
        ERC20 target = ERC20(adapterParams.target);
        target.safeTransferFrom(msg.sender, address(this), tBal); // pull target

        // redeem target for underlying
        uint256 uBalBefore = u.balanceOf(address(this));
        require(CTokenInterface(adapterParams.target).redeem(tBal) == 0, "Redeem failed");
        uint256 uBalAfter = u.balanceOf(address(this));
        uint256 uBal = uBalAfter - uBalBefore;

        // transfer underlying to sender
        u.safeTransfer(msg.sender, uBal);
        return uBal;
    }
}
