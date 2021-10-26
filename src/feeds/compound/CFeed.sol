// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseFeed } from "../BaseFeed.sol";

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);
    function decimals() external returns (uint256);
    function underlying() external returns (address);
}

/// @notice Feed contract for cTokens
contract CFeed is BaseFeed {
    using FixedMath for uint256;

    function _scale() internal virtual override returns (uint256) {
        CTokenInterface t = CTokenInterface(target);
        uint256 decimals = CTokenInterface(t.underlying()).decimals();
        return t.exchangeRateCurrent().fdiv(10**(10 + decimals), 10 ** decimals);
    }
}
