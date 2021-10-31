// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";

// Internal references
import { BaseFeed } from "../BaseFeed.sol";

interface WstETHInterface {
    /// @notice https://github.com/lidofinance/lido-dao/blob/master/contracts/0.6.12/WstETH.sol
    /// @dev returns the current exchange rate of stETH to wstETH in wei (18 decimals)
    function stEthPerToken() external view returns (uint256);
}

/// @notice Feed contract for wstETH
contract WstETHFeed is BaseFeed {
    using FixedMath for uint256;

    /// @return scale in wei (18 decimals)
    function _scale() internal virtual override returns (uint256) {
        WstETHInterface t = WstETHInterface(target);
        return t.stEthPerToken();
    }
}