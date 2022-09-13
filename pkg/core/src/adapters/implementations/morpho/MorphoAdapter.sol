// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// Internal references
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { MasterPriceOracle } from "../../implementations/oracles/MasterPriceOracle.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

/// @notice Adapter contract for Morpho vaults
contract MorphoAdapter is BaseAdapter {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    address public constant RARI_MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;
    ERC20 public constant MORPHO = ERC20(0x9994E35Db50125E0DF82e4c2dde62496CE330999);

    uint256 public immutable BASE_UINT;
    uint256 public immutable SCALE_FACTOR;

    address public immutable rewardRecipient;

    constructor(
        address _divider,
        address _target,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _rewardRecipient
    ) BaseAdapter(_divider, _target, address(ERC4626(_target).asset()), _ifee, _adapterParams) {
        uint256 tDecimals = ERC4626(target).decimals();
        BASE_UINT = 10**tDecimals;
        SCALE_FACTOR = 10**(18 - tDecimals); // we assume targets decimals <= 18
        rewardRecipient = _rewardRecipient;
        ERC20(underlying).approve(target, type(uint256).max);
    }

    function scale() external override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function scaleStored() external view override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        price = MasterPriceOracle(adapterParams.oracle).price(underlying);
        if (price == 0) {
            revert Errors.InvalidPrice();
        }
    }

    function wrapUnderlying(uint256 assets) external override returns (uint256 _shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        _shares = ERC4626(target).deposit(assets, msg.sender);
    }

    function unwrapTarget(uint256 shares) external override returns (uint256 _assets) {
        _assets = ERC4626(target).redeem(shares, msg.sender, msg.sender);
    }

    function claimRewards() external {
        MORPHO.safeTransfer(rewardRecipient, MORPHO.balanceOf(address(this)));
    }
}
