// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockToken } from "../../../tests/test-helpers/mocks/MockToken.sol"; // TODO: replace for MintableToken interface
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

interface WETHLike {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface RTokenLike {
    function pricePerShare() external view returns (uint256);

    function roundPricePerShare(uint256) external view returns (uint256);

    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    function vaultParams()
        external
        view
        returns (
            bool,
            uint8,
            address,
            address,
            uint56,
            uint104
        );

    function vaultState()
        external
        view
        returns (
            uint16,
            uint104,
            uint104,
            uint128,
            uint128
        );

    function depositETH() external payable; // RETH only

    function depositYieldToken(uint256) external payable;

    function maxRedeem() external payable;

    function completeWithdraw() external;

    function withdrawInstantly(uint256 amount, uint256) external;

    function initiateWithdraw(uint256 numShares) external;

    function depositReceipts(address)
        external
        returns (
            uint16 round,
            uint104 amount,
            uint128 unredeemedShares
        );
}

interface PriceOracleLike {
    function getPrice(address _asset) external view returns (uint256);
}

/// @notice Adapter contract for fTokens
contract RAdapter is BaseAdapter {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant FETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address public immutable rToken;
    address public immutable target2;
    bool public immutable isRETH;
    uint8 public immutable uDecimals;

    constructor(
        address _divider,
        address _target,
        address _target2,
        address _underlying,
        address _rToken, // TODO: remove from here? and do `ERC4626(_target).asset()`;
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {
        isRETH = _underlying == WETH; // TODO: use this udnerlying or _underlying??
        rToken = _rToken;
        target2 = _target2;

        ERC20(underlying).approve(rToken, type(uint256).max);
        uDecimals = ERC20(_underlying).decimals(); // TODO: use decimals from vaultParams?
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter) {
        super.notify(_usr, amt, join);
    }

    /// @return Exchange rate from Target to Underlying using Ribbon's `pricePerShare()`, normed to 18 decimals
    function scale() external override returns (uint256) {
        uint256 exRate = RTokenLike(rToken).pricePerShare();
        return _to18Decimals(exRate);
    }

    function scaleStored() external view override returns (uint256) {
        uint256 exRate = RTokenLike(rToken).pricePerShare();
        return _to18Decimals(exRate);
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        price = isRETH ? 1e18 : PriceOracleLike(adapterParams.oracle).getPrice(underlying);
    }

    /// @dev When wrapping underlying, we mint wrapped target tokens and send them to the user
    /// This is because Ribbon does not retun target immediately after a deposit is made
    /// The underlying is sent to Ribbon and stays as pending amount until the next round starts
    function wrapUnderlying(uint256 uBal) external override returns (uint256 tBal) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), uBal); // pull underlying

        // Deposit underlying on Ribbon
        // TODO: de we want to allow deposits directly in ETH?
        // TODO: check if to use depositYieldToken, depositFor or deposit (deposit does not exist for example on the RSTETH)
        if (isRETH) {
            WETHLike(WETH).withdraw(uBal); // unwrap WETH into ETH
            RTokenLike(rToken).depositETH{ value: uBal }();
        } else {
            RTokenLike(rToken).depositYieldToken(uBal);
        }

        uint256 pps = RTokenLike(rToken).pricePerShare();
        tBal = uBal.fdiv(pps);

        // if (underlying == STETH) tBal -= 1; // because stETH transfers suffer from an off-by-1 error (from RibbonVault.sol line 343) // TODO: do we need this?
        MockToken(target).mint(msg.sender, tBal); // mint wrapped target
    }

    /// @notice Unwrapping target is a 2-step process: `initiateUnwrapTarget` (see below) and `unwrapTarget` (line 224)
    /// `initiateUnwrapTarget` will:
    /// - pull user's wrapped target tokens (wTarget)
    /// - calculate how much those wTarget represent in Ribbon target (rTarget).
    /// - call Ribbon to initiate withdraw passing the rTarget amount
    /// - burn wTarget
    ///
    /// @dev when initiating an unwrap, we *check* (line 197) the pending underlying available in Ribbon
    /// and, if this amount is less or equal than the amount the user wants to unwrap
    /// we trigger a `withdrawInstantly` in Ribbon. We are doing this because of the following scenario:
    // - User A calls wrapUnderlying -> we mint wTarget at current pps
    // - ROUND CLOSES
    // - User B calls wrapUnderlying -> we mint wTarget at current pps
    // - User B calls `initiateUnwrapTarget` (without waiting for the round to be closed)
    // - - If we are not doing the *check* mentioned before and just trigger an `initiateWithdraw` in Ribbon,
    // we will starting a withdraw of rTarget frorm Ribbon while we should have been just withdrawing the
    // pending underlying and this will be conflicting with other user's positions that didn't want to intiate any withdrawal.
    function initiateUnwrapTarget(uint256 wtBal) external {
        (, uint104 pendingUnderlying, ) = RTokenLike(rToken).depositReceipts(address(this));
        RTokenLike(rToken).maxRedeem(); // TODO: maybe we can skip this and use unredeemShares?

        uint256 totalUnderlyingAvailable = pendingUnderlying + ERC20(underlying).balanceOf(address(this));
        uint256 totalTarget = ERC20(rToken).balanceOf(address(this));

        // total underlying is the sum of the pending underlying in Ribbon + any existing underlying balance in the adapter
        // + the adapter's target balance converted to underlying
        //
        // FIXME: the issue here is when trying to convert the total wrapped target tokens to underlying
        // because some of the total wTarget are backed by underlying and some by target. To calculate
        // the target-underlying conversion, we would probably need the pps of the previous round of each user's
        // deposit (which we don't have).
        // Below, we are using the current pps which is a higher one, making the target-underlying conversion
        // to give us more underlying which will give us a higher `totalUnderlying` number and the user will get more
        // than what he should.
        uint256 totalUnderlying = totalUnderlyingAvailable + totalTarget.fmul(RTokenLike(rToken).pricePerShare());

        // calculate how much underlying the wtBal represents (based on the totalUnderlying)
        uint256 totalSupply = MockToken(target).totalSupply();
        uint256 share = wtBal.fdiv(totalSupply, FixedMath.RAY);
        uint256 uBal = share.fmul(totalUnderlying, FixedMath.RAY);

        // A user might get an instant withdraw but this is not in every case
        if (uBal <= totalUnderlyingAvailable) {
            // Withdraw underlying
            RTokenLike(rToken).withdrawInstantly(uBal, 0);
            ERC20(underlying).transfer(msg.sender, uBal);
        } else {
            // calculate how much target the wtBal represent
            totalSupply = MockToken(target).totalSupply();
            share = wtBal.fdiv(totalSupply, FixedMath.RAY);
            uint256 tBal = share.fmul(totalTarget, FixedMath.RAY);

            // Mint wrapped target tokens 2
            MockToken(target2).mint(msg.sender, tBal);

            // Initiate withdrawal
            RTokenLike(rToken).initiateWithdraw(tBal);
        }

        // Burn wrapped target tokens
        MockToken(target).burn(msg.sender, wtBal);
    }

    /// `unwrapTarget` is the 2nd step:
    /// - pulls the user's wrapped target tokens 2
    /// - calls `ribbon.completeWithdraw` which sends underlying back to the adapter
    /// - calculates how much those wrapped target 2 represent in underlying
    /// - burns wrapped target 2
    /// - transfers underlying to user
    function unwrapTarget(uint256 wt2Bal) external override returns (uint256 uBal) {
        // Complete withdraw on Ribbon (will send underlying back)
        RTokenLike(rToken).completeWithdraw();

        // Calculate how much underlying the wt2Bal represent
        uint256 totalUnderlying = ERC20(underlying).balanceOf(address(this));
        uint256 totalSupply = MockToken(target2).totalSupply();
        uint256 share = wt2Bal.fdiv(totalSupply, FixedMath.RAY);
        uBal = share.fmul(totalUnderlying, FixedMath.RAY);

        if (isRETH) {
            // Deposit ETH into WETH contract
            (bool success, ) = WETH.call{ value: uBal }("");
            if (!success) revert Errors.TransferFailed();
        }

        // Burn wrapped target tokens
        MockToken(target2).burn(msg.sender, wt2Bal);

        // Transfer underlying to sender
        ERC20(underlying).safeTransfer(msg.sender, uBal);
    }

    event Log(uint256);

    function _to18Decimals(uint256 exRate) internal view returns (uint256) {
        // "pricePerShare() returns the price of a unit of share denominated in the `asset`
        // (using the decicmals of the asset)

        // The equation to norm an asset to 18 decimals is:
        // `num * 10**(18 - decimals)`
        return uDecimals >= 18 ? exRate / 10**(uDecimals - 18) : exRate * 10**(18 - uDecimals);
    }

    /* ========== FALLBACK ========== */

    fallback() external payable {}
}
