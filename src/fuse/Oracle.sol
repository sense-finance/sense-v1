// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

/// @title Price Oracle
/// @author Compound
/// @notice The minimum interface a contract must implement in order to work as an oracle in Fuse
/// Taken from: https://github.com/Rari-Capital/compound-protocol/blob/fuse-final/contracts/PriceOracle.sol
abstract contract PriceOracle {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /// @notice Get the underlying price of a cToken asset
    /// @param cToken The cToken to get the underlying price of
    /// @return The underlying asset price mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function getUnderlyingPrice(CTokenLike cToken) external view virtual returns (uint256);
}

interface CTokenLike {
    function underlying() external view returns (address);
}

/// @title Sense Oracle
/// @notice A fuse-copmatible oracle for Zeros, Claims, and Targets supported by Sense
contract Zero is PriceOracle {
    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    function getUnderlyingPrice(CTokenLike cToken) public view override returns (uint256) {
        address underlying = cToken.underlying();
        // get the Zero
    }
}

// contract Claim is PriceOracle {
//     mapping(address => uint) prices;
//     event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

//     function getUnderlyingPrice(CTokenLike cToken) public view returns (uint) {
//         // Get underlying price from ___ protocol
       
//     }
// }

contract Target is PriceOracle {
    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    function getUnderlyingPrice(CTokenLike cToken) public view override returns (uint256) {
        // Get underlying price from ___ protocol
        address target = CTokenLike(cToken).underlying();
        
    }
}

// Zero:
// * uni TWAP (guarded within bounds)? or price tied to underlying redeemable value at maturity?
// Claim:
// * uni TWAP? or price tied to rate expectations? tied to principal?
// Target:
// * Target's unerlying value (so, for ex, how much DAI is the cDAI redeemable for)
