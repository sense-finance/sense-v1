// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Token } from "../tokens/Token.sol";
import { Divider } from "../Divider.sol";
import { Claim } from "../tokens/Claim.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";

/// @title Claim Recycler
/// @notice You can use this contract to amplify the FY component of your Claims
/// @dev The majority of the business logic in this contract deals with the auction
contract Recycler is Trust {
    using SafeERC20 for ERC20;

    uint256 public constant AUCTION_SPEED = 0.001e18; // Zero lot size decreases by 0.001 each second

    mapping(address => uint256) private totalDeposits;
    mapping(address => uint256) private tick;
    mapping(address => mapping(address => uint256)) private deposits;
    mapping(address => mapping(address => uint256)) private marks;
    mapping(address => Auction) private auctions;
    mapping(address => uint256) private ids;
    mapping(address => uint256) private multipliers;
    mapping(address => RClaim) private rclaims;
    Divider public divider;
    struct Config {
        uint256 dustLimit;
        uint256 discountThreshold;
        uint256 cadence;
    }
    struct RClaim {
        uint256 collected;
        uint256 lastKick;
        Config config;
        Token token;
    }
    struct Auction {
        uint256 lot;
        uint256 rho;
        uint256 discount;
    }

    constructor(address _divider) Trust(msg.sender) {
        divider = Divider(_divider);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Transfer Claims from the caller
    /// @dev Determines Claim type by calling Sense Core with the token address
    /// @dev Track the timestamp of the deposit
    /// @param feed Address of feed for Claim token that msg.sender is depositing
    /// @param maturity Maturity date (timestamp) for Claim tokens that msg.sender is depositing
    /// @param balance Amount of Claims to transfer from the caller
    function join(
        address feed,
        uint256 maturity,
        uint256 balance
    ) public {
        (, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), "Series must exist");
        require(!_auctionActive(claim), "Auction active for this Claim");

        ERC20(claim).safeTransferFrom(msg.sender, address(this), balance);
        rclaims[claim].token.mint(msg.sender, balance);

        deposits[msg.sender][claim] += balance * multipliers[claim];
        totalDeposits[claim] += balance;
    }

    /// @notice Transfer Claims and associated PY to the caller
    /// @param feed Address of feed for Claim token that msg.sender is withdrawing
    /// @param maturity Maturity date (timestamp) for Claim tokens that msg.sender is withdrawing
    /// @param balance Amount of Claims to transfer to the caller
    function exit(
        address feed,
        uint256 maturity,
        uint256 balance
    ) public {
        (, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), "Series must exist");

        ERC20(claim).safeTransfer(msg.sender, balance);
        rclaims[claim].token.burn(msg.sender, balance);

        // Can't be on auction
        require(!_auctionActive(claim), "Auction active for this Claim");

        deposits[msg.sender][claim] -= balance;
        totalDeposits[claim] -= balance;
    }

    /// @notice Update configuration parameter
    /// @param feed Address of feed that Recycle Claim params are being changed for
    /// @param maturity Maturity date (timestamp) for the Claim
    /// @param params new value for the parameter
    function file(
        address feed,
        uint256 maturity,
        Config calldata params
    ) public requiresTrust {
        (, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(rclaims[claim].token != ERC20(address(0)), "rClaim hasn't yet been initialized");
        rclaims[claim].config = params;
    }

    /// @notice Initialize a new Claim
    /// @param feed Address of feed for Claim token user is initializing
    /// @param maturity maturity Maturity date (timestamp) for the Claim
    /// @param params Configuration struct to set all of the initial variables needed for a Claim type
    function init(
        address feed,
        uint256 maturity,
        Config calldata params
    ) public requiresTrust {
        (, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), "Series must exist");
        require(rclaims[claim].token == ERC20(address(0)), "rClaim type has already been initialized");

        // Only applies to future auctions
        string memory name = string(abi.encodePacked("R-", ERC20(claim).name(), "-R"));
        string memory symbol = string(abi.encodePacked("R-", ERC20(claim).symbol(), "-R"));
        rclaims[claim].token = new Token(name, symbol, ERC20(Feed(feed).target()).decimals(), address(this));
        // NOTE: Default to mainnet chainId for now.
        rclaims[claim].config = params;
        rclaims[claim].lastKick = block.timestamp;

        multipliers[claim] = 1 ether;
    }

    /// @notice Start an auction for a specific Series
    function kick(address feed, uint256 maturity) public {
        (, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), "Series must exist");
        require(!_auctionActive(claim), "Auction already active for this Claim");

        require(
            block.timestamp - rclaims[claim].lastKick > rclaims[claim].config.cadence,
            "Not enough time has passed since last auction"
        );

        // Amount of target collected
        uint256 collected = Claim(claim).collect();
        require(collected > rclaims[claim].config.discountThreshold, "Not enough yield to collect for an auction");

        auctions[claim].discount = collected;
        // Kick off the auction looking for
        auctions[claim].lot = 100 ether * collected; // starting price: 100/101 -> 0.99
    }

    /// @notice Takes some amount of the lot of Zeros currently on auction for the given Claim token
    /// @param feed Address of feed for Claim token user is initializing
    /// @param maturity Claim type identifier
    /// @param balance Balance of Zeros caller is buying
    function take(
        address feed,
        uint256 maturity,
        uint256 balance
    ) public {
        (address zero, address claim, , , , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), "Series must exist");

        uint256 lot = _getLotSize(claim);
        require(balance <= lot, "Must take less than or equal to lot size");

        // Take the users Target
        uint256 discount = auctions[claim].discount;
        ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, address(this), balance - discount);

        // Use it plus the Target collected for this auction to issue new Zeros and Claims
        divider.issue(feed, maturity, balance);
        // Send all the Zeros back to the sender
        ERC20(zero).safeTransfer(msg.sender, balance);

        // TODO: double check this equation
        multipliers[claim] = ERC20(claim).balanceOf(address(this)) / totalDeposits[claim];

        // Decrement lot size appropriately
        auctions[claim].lot -= (auctions[claim].lot / lot) * balance;
        require(
            auctions[claim].lot - discount >= rclaims[claim].config.dustLimit,
            "Must leave more than the dust limit"
        );
    }

    /* ========== VIEW FUNCTIONS ========== */

    function _getLotSize(address claim) public view returns (uint256 lot) {
        lot = auctions[claim].lot * ((block.timestamp - auctions[claim].rho) * AUCTION_SPEED);
    }

    function _auctionActive(address claim) internal view returns (bool active) {
        active = auctions[claim].lot - auctions[claim].discount >= rclaims[claim].config.dustLimit;
    }
}