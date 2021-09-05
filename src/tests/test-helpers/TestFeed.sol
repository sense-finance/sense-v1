pragma solidity ^0.8.6;

// Internal references
import "../../BaseFeed.sol";

contract TestFeed is BaseFeed {

    constructor(
        address _target,
        string memory _name,
        string memory _symbol
    ) public BaseFeed(_target, _name, _symbol) {}

    /// @notice Calculate and return this feed's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate,
    /// or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @return _scale 18 decimal Scale value
    function scale() external override virtual returns (uint256 _scale) {
        return 1;
    }
}
