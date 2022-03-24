// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseAdapter } from "../BaseAdapter.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

interface WstETHLike {
    /// @notice https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
    /// @dev returns the current exchange rate of stETH to wstETH in wei (18 decimals)
    function stEthPerToken() external view returns (uint256);

    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface StETHLike {
    /// @notice Send funds to the pool with optional _referral parameter
    /// @dev This function is alternative way to submit funds. Supports optional referral address.
    /// @return Amount of StETH shares generated
    function submit(address _referral) external payable returns (uint256);

    /// @return the amount of tokens owned by the `_account`.
    ///
    /// @dev Balances are dynamic and equal the `_account`'s share in the amount of the
    /// total Ether controlled by the protocol. See `sharesOf`.
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    ///@return the amount of tokens owned by the `_account`.
    ///
    ///@dev Balances are dynamic and equal the `_account`'s share in the amount of the
    ///total Ether controlled by the protocol. See `sharesOf`.
    function balanceOf(address _account) external view returns (uint256);
}

interface CurveStableSwapLike {
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

interface WETHLike {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface StEthPriceFeedLike {
    function safe_price_value() external view returns (uint256);
}

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    address public constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant CURVESINGLESWAP = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETHPRICEFEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;

    // On 2022.02.28, a swap from 100k stETH ($250m+ worth) to ETH was quoted
    // by https://curve.fi/steth to incur 0.39% slippage, so we went with 0.5%
    // to capture practically all unwrap/wrap sizes through the Sense adapter."
    uint256 public constant SLIPPAGE_TOLERANCE = 0.005e18;

    /// @notice Cached scale value from the last call to `scale()`
    uint256 public override scaleStored;

    constructor(
        address _divider,
        address _oracle,
        uint256 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt
    ) BaseAdapter(_divider, WSTETH, WETH, _oracle, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _tilt, 31) {
        // approve wstETH contract to pull stETH (used on wrapUnderlying())
        ERC20(STETH).approve(WSTETH, type(uint256).max);
        // approve Curve stETH/ETH pool to pull stETH (used on unwrapTarget())
        ERC20(STETH).approve(CURVESINGLESWAP, type(uint256).max);
        // set an inital cached scale value
        scaleStored = _wstEthToEthRate();
    }

    /// @return exRate Eth per wstEtH (natively in 18 decimals)
    function scale() external virtual override returns (uint256 exRate) {
        exRate = _wstEthToEthRate();

        if (exRate != scaleStored) {
            // update value only if different than the previous
            scaleStored = exRate;
        }
    }

    function getUnderlyingPrice() external pure override returns (uint256 price) {
        price = 1e18;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256 eth) {
        ERC20(WSTETH).safeTransferFrom(msg.sender, address(this), amount); // pull wstETH
        uint256 stEth = WstETHLike(WSTETH).unwrap(amount); // unwrap wstETH into stETH

        // exchange stETH to ETH exchange on Curve
        // to calculate the minDy, we use Lido's safe_price_value() which should prevent from flash loan / sandwhich attacks
        // and we are also adding a slippage tolerance of 0.5%
        uint256 stEthEth = StEthPriceFeedLike(STETHPRICEFEED).safe_price_value(); // returns the cached stETH/ETH safe price

        eth = CurveStableSwapLike(CURVESINGLESWAP).exchange(
            int128(1),
            int128(0),
            stEth,
            stEthEth.fmul(stEth).fmul(FixedMath.WAD - SLIPPAGE_TOLERANCE)
        );

        // deposit ETH into WETH contract
        (bool success, ) = WETH.call{ value: eth }("");
        if (!success) revert Errors.TransferFailed();

        ERC20(WETH).safeTransfer(msg.sender, eth); // transfer WETH back to sender (periphery)
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256 wstETH) {
        ERC20(WETH).safeTransferFrom(msg.sender, address(this), amount); // pull WETH
        WETHLike(WETH).withdraw(amount); // unwrap WETH into ETH
        StETHLike(STETH).submit{ value: amount }(address(0)); // stake ETH (returns wstETH)
        uint256 stEth = StETHLike(STETH).balanceOf(address(this));
        ERC20(WSTETH).safeTransfer(msg.sender, wstETH = WstETHLike(WSTETH).wrap(stEth)); // transfer wstETH to msg.sender
    }

    function _wstEthToEthRate() internal view returns (uint256 exRate) {
        // In order to account for the stETH/ETH CurveStableSwap rate,
        // we use `safe_price_value` from Lido's stETH price feed.
        // https://docs.lido.fi/contracts/steth-price-feed#steth-price-feed-specification
        uint256 stEthEth = StEthPriceFeedLike(STETHPRICEFEED).safe_price_value(); // returns the cached stETH/ETH safe price
        uint256 wstETHstETH = StETHLike(STETH).getPooledEthByShares(1 ether); // stETH tokens per one wstETH
        exRate = stEthEth.fmul(wstETHstETH);
    }

    fallback() external payable {
        if (msg.sender != WETH && msg.sender != CURVESINGLESWAP) revert Errors.SenderNotEligible();
    }
}
