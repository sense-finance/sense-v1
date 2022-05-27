// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { CropAdapter } from "./CropAdapter.sol";

interface PriceOracleLike {
    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function price(address underlying) external view returns (uint256);
}

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626CropAdapter is CropAdapter {
    using SafeTransferLib for ERC20;

    uint256 public immutable BASE_UINT;
    uint256 public immutable SCALE_FACTOR;

    constructor(
        address _divider,
        address _target,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) CropAdapter(_divider, _target, address(ERC4626(_target).asset()), _ifee, _adapterParams, _reward) {
        uint256 tDecimals = ERC4626(target).decimals();
        BASE_UINT = 10**tDecimals;
        SCALE_FACTOR = 10**(18 - tDecimals); // we assume targets decimals <= 18
        ERC20(underlying).approve(target, type(uint256).max);
    }

    function scale() external override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function scaleStored() external view override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return PriceOracleLike(adapterParams.oracle).price(underlying);
    }

    function wrapUnderlying(uint256 assets) external override returns (uint256 _shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        _shares = ERC4626(target).deposit(assets, msg.sender);
    }

    function unwrapTarget(uint256 shares) external override returns (uint256 _assets) {
        _assets = ERC4626(target).redeem(shares, msg.sender, msg.sender);
    }
}
