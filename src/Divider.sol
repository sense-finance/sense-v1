pragma solidity ^0.8.6;

// Internal references
import "./interfaces/IDivider.sol";

/// @title Divide tokens in two
/// @notice You can use this contract to issue and redeem Sense ERC20 Zeros and Claims
/// @dev The implementation of the following function will likely require utility functions and/or libraries,
/// the usage thereof is left to the implementer
contract Divider is IDivider {

    address public govAddress = 0x0000000000000000000000000000000000000000;

    /// @notice Initilizes a new Series
    /// @dev Reverts if the feed hasn't been approved or if the Maturity date is invalid
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Configures/ deploys AMM pools for the new Zeros
    /// @dev Transfers some fixed amount of stable asset to this contract
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external override {
        return;
    }

    /// @notice Settles a Series and transfer a settlement reward to the caller
    /// @dev The Series' sponsor has a buffer where only they can settle the Series
    /// @dev After the buffer, the reward becomes MEV
    /// @dev Public because the implementer might want to auto-call settle series if someone tries to redeem
    /// a Series that has matured but hasn't been offically settled yet
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) public override {
        return;
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @dev Initializes the Series if it does not already exist
    /// @dev Pulls Target from the caller and takes the Issuance Fee out of their Zero & Claim share
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Balance of Zeros and Claims to mint the user –
    /// the same as the amount of Target they must deposit (less fees)
    function issue(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        return;
    }

    /// @notice Burn Zeros and Claims of a specific Series
    /// @dev Reverts if the Series doesn't exist
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Balance of Zeros and Claims to burn
    function combine(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        return;
    }

    /// @notice Burn Zeros of a Series after maturity
    /// @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    /// @dev Settles the series if it hasn't been done already and is in the settlement window (Idempotent)
    /// @dev The balance of Fixed Zeros to burn is a function of the change in Scale
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Amount of target User is claiming from the feed
    function redeemZero(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        return;
    }

    /// @notice Collect Claim excess before or at/after maturity
    /// @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    /// @dev Reverts if not called by the Claim contract directly
    /// @dev Burns the claim tokens if it's currently at or after maturity as this will be the last possible collect
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Amount of target User is claiming from the feed
    function collect(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        return;
    }

    // --- administration ---

    /// @notice Enable or disable an feed
    /// @dev Store the feed address in a registry for easy access on-chain
    /// @param feed Feedr's address
    /// @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) external onlyGov override {
        return;
    }

    /// @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    /// @dev Reverts if the Series has already been settled or if the maturity is invalid
    /// @dev Reverts if the Scale value is larger than the Scale from issuance, or if its above a certain threshold
    /// @param feed Feed's address
    /// @param maturity Maturity date for the Series
    /// @param scale Value to set as the Series' Scale value at maturity
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 scale
    ) external onlyGov override {
        return;
    }

    function stop() external onlyGov override {
        return;
    }

    // --- modifiers ---
    function _onlyGov() internal view {
        require(msg.sender == address(govAddress), "Sender is not Gov");
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

}
