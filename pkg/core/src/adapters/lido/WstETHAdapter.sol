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
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface PriceOracleInterface {
    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function price(address underlying) external view virtual returns (uint256);
}

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter {
    using FixedMath for uint256;

    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
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
        return PriceOracleInterface(adapterParams.oracle).price(WETH);
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        uint256 stETH = WstETHInterface(WSTETH).unwrap(amount);
        uint256 minDy = ICurveStableSwap(CURVESINGLESWAP).get_dy(int128(1), int128(0), amount);
        uint256 eth = ICurveStableSwap(CURVESINGLESWAP).exchange(int128(1), int128(0), amount, minDy);
        (bool success, ) = WETH.call{ value: eth }("");
        require(success, "Transfer failed.");
        return eth;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        IWETH(WETH).withdraw(amount);
        (bool success, ) = STETH.call{ value: amount }("");
        require(success, "Transfer failed.");
        return WstETHInterface(WSTETH).wrap(amount);
    }
}
