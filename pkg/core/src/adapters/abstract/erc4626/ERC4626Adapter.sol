// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// Internal references
import { MasterPriceOracle } from "../../implementations/oracles/MasterPriceOracle.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { ExtractableReward } from "../extensions/ExtractableReward.sol";

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626Adapter is BaseAdapter, ExtractableReward {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    address public constant RARI_MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    uint256 public immutable BASE_UINT;
    uint256 public immutable SCALE_FACTOR;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    )
        BaseAdapter(_divider, _target, address(IERC4626(_target).asset()), _ifee, _adapterParams)
        ExtractableReward(_rewardsRecipient)
    {
        uint256 tDecimals = IERC4626(target).decimals();
        uint256 uDecimals = IERC4626(underlying).decimals();
        BASE_UINT = 10**tDecimals;
        SCALE_FACTOR = 10**(18 - uDecimals); // we assume targets decimals <= 18
        ERC20(underlying).safeApprove(target, type(uint256).max);
    }

    function scale() external override returns (uint256) {
        return IERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function scaleStored() external view override returns (uint256) {
        return IERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        price = MasterPriceOracle(adapterParams.oracle).price(underlying);
        if (price == 0) {
            revert Errors.InvalidPrice();
        }
    }

    function wrapUnderlying(uint256 assets) external override returns (uint256 _shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        _shares = IERC4626(target).deposit(assets, msg.sender);
    }

    function unwrapTarget(uint256 shares) external override returns (uint256 _assets) {
        _assets = IERC4626(target).redeem(shares, msg.sender, msg.sender);
    }

    function _isValid(address _token) internal virtual override returns (bool) {
        return (_token != target && _token != adapterParams.stake);
    }
}
