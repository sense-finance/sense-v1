// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseAdapter } from "../BaseAdapter.sol";

interface WstETHInterface {
    /// @notice https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
    /// @dev returns the current exchange rate of stETH to wstETH in wei (18 decimals)
    function stEthPerToken() external view returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface stETHInterface {
    /**
    * @notice Send funds to the pool with optional _referral parameter
    * @dev This function is alternative way to submit funds. Supports optional referral address.
    * @return Amount of StETH shares generated
    */
    function submit(address _referral) external payable returns (uint256);
}

interface ICurveStableSwap {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}


interface PriceOracleInterface {
    /// @notice Get the underlying price of a cToken asset
    /// @param cToken The cToken to get the underlying price of
    /// @return The underlying asset price mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function getUnderlyingPrice(CTokenInterface cToken) external view returns (uint256);
}

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
    function mint(uint mintAmount) external returns (uint);

    /// The redeem function converts a specified quantity of cTokens into the underlying asset, and returns
    /// them to the user. The amount of underlying tokens received is equal to the quantity of cTokens redeemed,
    /// multiplied by the current Exchange Rate. The amount redeemed must be less than the user's Account Liquidity
    /// and the market's available liquidity.
    /// @param redeemTokens The number of cTokens to be redeemed.
    /// @return 0 on success, otherwise an Error code
    function redeem(uint redeemTokens) external returns (uint);
}

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter {
    using FixedMath for uint256;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    /// @return scale in wei (18 decimals)
    function _scale() internal virtual override returns (uint256) {
        WstETHInterface t = WstETHInterface(adapterParams.target);
        return t.stEthPerToken();
    }

    function underlying() external view override returns (address) {
        return WETH;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return PriceOracleInterface(adapterParams.oracle).getUnderlyingPrice(
            CTokenInterface(adapterParams.target)
        );
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        uint256 stETH = WstETHInterface(WSTETH).unwrap(amount);
        uint256 minDy = ICurveStableSwap(CURVESINGLESWAP).get_dy(int128(1), int128(0), amount);
        uint256 eth = ICurveStableSwap(CURVESINGLESWAP).exchange(int128(1), int128(0), amount, minDy);
        (bool success, ) = WETH.call{value: eth}("");
        require(success, "Transfer failed.");
        return eth;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        IWETH(WETH).withdraw(amount);
        (bool success, ) = STETH.call{value: amount}("");
        require(success, "Transfer failed.");
        return WstETHInterface(WSTETH).wrap(amount);
    }
}