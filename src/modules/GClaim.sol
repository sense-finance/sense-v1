// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "solmate/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/errors.sol";
import { Claim } from "../tokens/Claim.sol";
import { Token } from "../tokens/Token.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";

/// @title Gravity Claims (gClaims)
/// @notice The GClaim contract turns Collect Claims into Drag Claims
contract GClaim {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    /// @notice "Issuance" scale value all claims of the same Series must backfill to separated by Claim address.
    mapping(address => uint256) public inits;
    /// @notice Total amount of interest collected separated by Claim address.
    mapping(address => uint256) public totals;
    mapping(address => Token) public gclaims;
    Divider public divider;

    constructor(address _divider) {
        divider = Divider(_divider);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function join(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(maturity > block.timestamp, Errors.InvalidMaturity);

        (, address claim, , , , , ) = divider.series(feed, maturity);
        require(claim != address(0), Errors.SeriesDoesntExists);

        if (address(gclaims[claim]) == address(0)) {
            // If this is the first Claim from this Series:
            // * Set the current scale value as the floor
            // * Deploy a new gClaim contract

            // NOTE: Because we're transferring Claims in this same TX, we could technically
            // get the scale value from the divider, but that's a little opaque as it relies on side-effects,
            // so i've gone with the clearest solution for now and we can optimize later
            inits[claim] = Feed(feed).scale();
            string memory name = string(abi.encodePacked("G-", ERC20(claim).name(), "-G"));
            string memory symbol = string(abi.encodePacked("G-", ERC20(claim).symbol(), "-G"));
            // NOTE: Consider the benefits of using Create2 here
            gclaims[claim] = new Token(name, symbol, ERC20(Feed(feed).target()).decimals());
        } else {
            uint256 initScale = inits[claim];
            uint256 currScale = Feed(feed).scale();
            // Calculate the amount of excess that has accrued since
            // the first Claim from this Series was deposited
            if (currScale - initScale > 0) {
                uint256 gap = (balance * currScale) / (currScale - initScale) / 10**18;

                // Pull the amount of Target needed to backfill the excess
                ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, address(this), gap);
                totals[claim] += gap;
            }
        }
        // NOTE: Is there any way to drag inits up for everyone after a certain about of time has passed?

        // Pull Collect Claims to this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), balance);
        // Mint the user Drag Claims
        gclaims[claim].mint(msg.sender, balance);

        emit Join(feed, maturity, msg.sender, balance);
    }

    function exit(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        (, address claim, , , , , ) = divider.series(feed, maturity);

        require(claim != address(0), Errors.SeriesDoesntExists);

        // Collect excess for all Claims from this Series in this contract holds
        uint256 collected = Claim(claim).collect();
        // Track the total Target collected manually so that that we don't get
        // mixed up when multiple Series have the same Target
        uint256 total = totals[claim] + collected;

        // Determine the percent of the excess this caller has a right to
        uint256 rights = (
            balance.fdiv(gclaims[claim].totalSupply(), Token(claim).BASE_UNIT()).fmul(total, Token(claim).BASE_UNIT())
        );
        total -= rights;
        totals[claim] = total;

        // Send the excess Target back to the user
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, rights);
        // Transfer Collect Claims back to the user
        ERC20(claim).safeTransfer(msg.sender, balance);
        // Burn the user's gclaims
        gclaims[claim].burn(msg.sender, balance);

        emit Exit(feed, maturity, msg.sender, balance);
    }

    // NOTE: Admin pull up issuance?
    // NOTE: Admin approved claims?

    /* ========== EVENTS ========== */

    event Join(address indexed feed, uint256 maturity, address indexed guy, uint256 balance);
    event Exit(address indexed feed, uint256 maturity, address indexed guy, uint256 balance);
}
