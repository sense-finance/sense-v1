// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// @title Compound's InterestRateModel Interface
/// @author Compound
/// @notice The minimum interface a contract must implement in order to work as an interest rate model in Fuse
/// Taken from: https://github.com/Rari-Capital/compound-protocol/blob/fuse-final/contracts/InterestRateModel.sol
abstract contract IRModel {
    /// @notice Indicator that this is an InterestRateModel contract (for inspection)
    bool public constant isInterestRateModel = true;

    /// @notice Calculates the current borrow interest rate per block
    /// @param cash The total amount of cash the market has
    /// @param borrows The total amount of borrows the market has outstanding
    /// @param reserves The total amount of reserves the market has
    /// @return The borrow rate per block (as a percentage, and scaled by 1e18)
    function getBorrowRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves
    ) external view virtual returns (uint256);

    /// @notice Calculates the current supply interest rate per block
    /// @param cash The total amount of cash the market has
    /// @param borrows The total amount of borrows the market has outstanding
    /// @param reserves The total amount of reserves the market has
    /// @param reserveFactorMantissa The current reserve factor the market has
    /// @return The supply rate per block (as a percentage, and scaled by 1e18)
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view virtual returns (uint256);
}
