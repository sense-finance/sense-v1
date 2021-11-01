// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { CropFeed } from "../CropFeed.sol";

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);

    function decimals() external returns (uint256);

    function underlying() external returns (address);

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

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

/// @notice Feed contract for cTokens
contract CFeed is CropFeed {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    function _scale() internal virtual override returns (uint256) {
        CTokenInterface t = CTokenInterface(feedParams.target);
        uint256 decimals = CTokenInterface(t.underlying()).decimals();
        return t.exchangeRateCurrent().fdiv(10**(10 + decimals), 10 ** decimals);
    }

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }

    function underlying() external override returns (address) {
        return CTokenInterface(feedParams.target).underlying();
    }

    function wrapUnderlying(uint256 uBal) external virtual override returns (uint256) {
        ERC20 target = ERC20(feedParams.target);
        uint256 tBalBefore = target.balanceOf(address(this));
        require(CTokenInterface(address(target)).mint(uBal) == 0, "Mint failed");
        uint256 tBalAfter = target.balanceOf(address(this));
        uint256 tBal = tBalAfter - tBalBefore;
        target.safeTransfer(msg.sender, tBal);
        return tBal;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        address target = feedParams.target;
        ERC20 u = ERC20(CTokenInterface(target).underlying());
        uint256 uBalBefore = u.balanceOf(address(this));
        require(CTokenInterface(target).redeem(tBal) == 0, "Redeem failed");
        uint256 uBalAfter = u.balanceOf(address(this));
        uint256 uBal = uBalAfter - uBalBefore;
        u.safeTransfer(msg.sender, uBal);
        return uBal;
    }
}
