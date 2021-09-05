pragma solidity ^0.8.6;

// Internal references
import "./interfaces/IFeed.sol";

/// @title Assign time-based value to target assets
/// @dev In most cases, the only function that will be unique to each feed type is `scale`
abstract contract BaseFeed is IFeed {
    // The Target token's address this feed applies to
    address public override target;

    // Name and symbol for this feed
    string public override name;
    string public override symbol;
    // TODO: address of the external contract to call
    // TODO: change address (in case something has failed) onlyGov??

    constructor(address _target, string memory _name, string memory _symbol) {
        target = _target;
        name = _name;
        symbol = _symbol;
    }

    /// @notice Calculate and return this feed's Scale value for the current timestamp
    /// @dev For some Targets, such as cTokens, this is simply the exchange rate,
    /// or `supply cToken / supply underlying`
    /// @dev For other Targets, such as AMM LP shares, specialized logic will be required
    /// @return _scale 18 decimal Scale value
    function scale() external override virtual returns (uint256 _scale);
}
