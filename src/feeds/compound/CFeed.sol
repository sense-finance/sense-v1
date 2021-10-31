// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { CropFeed } from "../CropFeed.sol";

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);
    function decimals() external returns (uint256);
    function underlying() external returns (address);
}

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

/// @notice Feed contract for cTokens
contract CFeed is CropFeed {
    using FixedMath for uint256;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    function _scale() internal virtual override returns (uint256) {
        CTokenInterface t = CTokenInterface(feedParams.target);
        uint256 decimals = CTokenInterface(t.underlying()).decimals();
        return t.exchangeRateCurrent().fdiv(10**(10 + decimals), 10 ** decimals);
    }

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }
}
