// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseAdapter } from "../BaseAdapter.sol";
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

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

interface StEthPriceFeed {
    function safe_price_value() external returns (uint256);
}

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETHPRICEFEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint256 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint128 _minm,
        uint128 _maxm,
        uint8 _mode,
        uint128 _tilt
    ) BaseAdapter(_divider, _target, _oracle, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _tilt, 7) {
        // approve wstETH contract to pull stETH (used on wrapUnderlying())
        ERC20(STETH).safeApprove(WSTETH, type(uint256).max);
        // approve Curve stETH/ETH pool to pull stETH (used on unwrapTarget())
        ERC20(STETH).safeApprove(CURVESINGLESWAP, type(uint256).max);
    }

    /// @return Eth per wstEtH (natively in 18 decimals)
    function _scale() internal virtual override returns (uint256) {
        // In order to account for the stETH/ETH CurveStableSwap rate, we use `safe_price_value` from Lido's stETH price feed.
        // https://docs.lido.fi/contracts/steth-price-feed#steth-price-feed-specification
        uint256 stEthEth = StEthPriceFeed(STETHPRICEFEED).safe_price_value(); // returns the cached stETH/ETH safe price
        uint256 wstETHstETH = WstETHInterface(target).stEthPerToken(); // stETH tokens corresponding to one wstETH
        return stEthEth.fmul(wstETHstETH, FixedMath.WAD);
    }

    function underlying() external view override returns (address) {
        return WETH;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return 1e18;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        ERC20(WSTETH).safeTransferFrom(msg.sender, address(this), amount); // pull wstETH
        uint256 stETH = WstETHInterface(WSTETH).unwrap(amount); // unwrap wstETH into stETH

        // exchange stETH to ETH exchange on Curve
        uint256 minDy = ICurveStableSwap(CURVESINGLESWAP).get_dy(int128(1), int128(0), amount);
        uint256 eth = ICurveStableSwap(CURVESINGLESWAP).exchange(int128(1), int128(0), amount, minDy);

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

    fallback() external payable {
        require(msg.sender == WETH || msg.sender == CURVESINGLESWAP, Errors.SenderNotEligible);
    }
}
