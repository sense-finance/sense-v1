// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// External references
import { BaseAdapter } from "../BaseAdapter.sol";
import { FixedMath } from "../../external/FixedMath.sol";

interface CurvePoolLike {
    function remove_liquidity_one_coin(uint256 _token_amount, uint256 i, uint256 min_amount) external;

    // TODO: should this be calldata
    function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount) external;

    function coins(uint256 index) external view returns (address);
}

// TODO: receive WETH?
// TODO: which curve pools does this apply to

/// @notice Adapter contract for Curve pools
contract CurveAdapter is BaseAdapter {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    CurvePoolLike public immutable pool;

    uint256 public immutable coinIndex;

    // On 2022.02.28, a swap from 100k stETH ($250m+ worth) to ETH was quoted
    // by https://curve.fi/steth to incur 0.39% slippage, so we went with 0.5%
    // to capture practically all unwrap/wrap sizes through the Sense adapter."
    uint256 public constant SLIPPAGE_TOLERANCE = 0.005e18;

    /// @notice Cached scale value from the last call to `scale()`
    uint256 public override scaleStored;

    constructor(
        CurvePoolLike _pool,
        address _lpToken,
        uint256 _coinIndex,
        address _divider,
        address _oracle,
        uint256 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt
    ) BaseAdapter(
        _divider,
        _lpToken,
        _pool.coins(_coinIndex),
        _oracle,
        _ifee,
        _stake,
        _stakeSize,
        _minm,
        _maxm,
        _mode,
        _tilt,
        31
    ) {
        pool = _pool;
        coinIndex = _coinIndex;

        // approve Curve stETH/ETH pool to pull stETH (used on unwrapTarget())
        ERC20(underlying).approve(target, type(uint256).max);

        // set an inital cached scale value
        scaleStored = _scale();
    }

    /// @return exRate 
    function scale() external virtual override returns (uint256 exRate) {
        exRate = 1e18;

        if (exRate != scaleStored) {
            // update value only if different than the previous
            scaleStored = exRate;
        }
    }

    function _scale() internal view returns (uint256 exRate) {
        exRate = 1e18;
    }

    function getUnderlyingPrice() external pure override returns (uint256) {
        return 1e18;
    }

    function unwrapTarget(uint256 shares) external override returns (uint256 assets) {
        ERC20(target).safeTransferFrom(msg.sender, address(this), shares);
        uint256 min_amount = 0; // FIXME

        uint256 prebal = ERC20(underlying).balanceOf(msg.sender);
        pool.remove_liquidity_one_coin(shares, coinIndex, min_amount);
        uint256 postbal = ERC20(underlying).balanceOf(msg.sender);

        // TODO: should this error use an arg?
        if (postbal <= prebal) revert Errors.BadPoolInteraction();

        ERC20(underlying).safeTransfer(msg.sender, assets = postbal - prebal);
    }

    function wrapUnderlying(uint256 assets) external override returns (uint256 shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        uint256 min_mint_amount = 0; // FIXME

        uint256[] memory amounts = new uint256[](3); // FIXME
        amounts[coinIndex] = assets;

        uint256 prebal = ERC20(target).balanceOf(msg.sender);
        pool.add_liquidity(amounts, min_mint_amount);
        uint256 postbal = ERC20(target).balanceOf(msg.sender);

        if (postbal <= prebal) revert Errors.BadPoolInteraction();

        ERC20(target).safeTransfer(msg.sender, shares = postbal - prebal);
    }
}
