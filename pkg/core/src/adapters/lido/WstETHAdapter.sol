// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseAdapter } from "../BaseAdapter.sol";
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

interface WstETHInterface {
    /// @notice https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
    /// @dev returns the current exchange rate of stETH to wstETH in wei (18 decimals)
    function stEthPerToken() external view returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface StETHInterface {
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

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    uint256 public _lscale;

    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    uint256 public constant SLIPPAGE_TOLERANCE = 0.5e18;

    function initialize(address _divider, AdapterParams memory _adapterParams) public virtual override initializer {
        // approve wstETH contract to pull stETH (used on wrapUnderlying())
        ERC20(STETH).safeApprove(WSTETH, type(uint256).max);
        // approve Curve stETH/ETH pool to pull stETH (used on unwrapTarget())
        ERC20(STETH).safeApprove(CURVESINGLESWAP, type(uint256).max);
        super.initialize(_divider, _adapterParams);
    }

    /// @return scale in wei (18 decimals)
    function scale() external override returns (uint256) {
        WstETHInterface t = WstETHInterface(adapterParams.target);
        _lscale = t.stEthPerToken();
        return _lscale;
    }

    function scaleStored() external view override returns (uint256) {
        return _lscale;
    }

    function underlying() external view override returns (address) {
        return WETH;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return 1e18;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        ERC20(WSTETH).safeTransferFrom(msg.sender, address(this), amount); // pull wstETH
        WstETHInterface(WSTETH).unwrap(amount); // unwrap wstETH into stETH

        // exchange stETH to ETH exchange on Curve
        uint256 minDy = ICurveStableSwap(CURVESINGLESWAP).get_dy(int128(1), int128(0), amount);
        uint256 eth = ICurveStableSwap(CURVESINGLESWAP).exchange(
            int128(1),
            int128(0),
            amount,
            (minDy * (100e18 - SLIPPAGE_TOLERANCE)) / 100e18
        );

        // deposit ETH into WETH contract
        (bool success, ) = WETH.call{ value: eth }("");
        require(success, "Transfer failed.");

        ERC20(WETH).safeTransfer(msg.sender, eth); // transfer WETH back to sender (periphery)
        return eth;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        ERC20(WETH).safeTransferFrom(msg.sender, address(this), amount); // pull WETH
        IWETH(WETH).withdraw(amount); // unwrap WETH into ETH
        uint256 stETH = StETHInterface(STETH).submit{ value: amount }(address(0)); // stake ETH (returns wstETH)
        uint256 wstETH = WstETHInterface(WSTETH).wrap(stETH); // wrap stETH into wstETH
        ERC20(WSTETH).safeTransfer(msg.sender, wstETH); // transfer wstETH to msg.sender
    }

    fallback() external payable {}
}
