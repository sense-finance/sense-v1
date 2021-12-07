// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Claim } from "../tokens/Claim.sol";
import { Token } from "../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

/// @title Grounded Claims (gClaims)
/// @notice The GClaim Manager contract turns Collect Claims into Drag Claims
contract GClaimManager {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    /// @notice "Issuance" scale value all claims of the same Series must backfill to separated by Claim address
    mapping(address => uint256) public inits;
    /// @notice Total amount of interest collected separated by Claim address
    mapping(address => uint256) public totals;
    /// @notice The max scale value of different Series
    mapping(address => uint256) public mscales;
    mapping(address => Token) public gclaims;
    address public divider;

    constructor(address _divider) {
        divider = _divider;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function join(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) external {
        require(maturity > block.timestamp, Errors.InvalidMaturity);

        (, address claim, , , , , , , ) = Divider(divider).series(adapter, maturity);
        require(claim != address(0), Errors.SeriesDoesntExists);

        if (address(gclaims[claim]) == address(0)) {
            // If this is the first Claim from this Series:
            // * Set the current scale value as the floor
            // * Deploy a new gClaim contract

            // NOTE: Because we're transferring Claims in this same TX, we could technically
            // get the scale value from the divider, but that's a little opaque as it relies on side-effects,
            // so i've gone with the clearest solution for now and we can optimize later
            uint256 scale = Adapter(adapter).scale();
            mscales[claim] = scale;
            inits[claim] = scale;
            string memory name = string(abi.encodePacked("G-", ERC20(claim).name(), "-G"));
            string memory symbol = string(abi.encodePacked("G-", ERC20(claim).symbol(), "-G"));
            gclaims[claim] = new Token(name, symbol, ERC20(Adapter(adapter).getTarget()).decimals(), address(this));
        } else {
            uint256 tBal = excess(adapter, maturity, uBal);
            if (tBal > 0) {
                // Pull the amount of Target needed to backfill the excess back to issuance
                ERC20(Adapter(adapter).getTarget()).safeTransferFrom(msg.sender, address(this), tBal);
                totals[claim] += tBal;
            }
        }

        // Pull Collect Claims to this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), uBal);
        // Mint the user Drag Claims
        gclaims[claim].mint(msg.sender, uBal);

        emit Joined(adapter, maturity, msg.sender, uBal);
    }

    function exit(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) external {
        (, address claim, , , , , , , ) = Divider(divider).series(adapter, maturity);

        require(claim != address(0), Errors.SeriesDoesntExists);

        // Collect excess for all Claims from this Series this contract holds
        uint256 collected = Claim(claim).collect();
        // Track the total Target collected manually so that that we don't get
        // mixed up when multiple Series have the same Target
        uint256 total = totals[claim] + collected;

        // Determine how much of stored excess this caller has a right to
        uint256 tBal = uBal.fdiv(gclaims[claim].totalSupply(), total);
        totals[claim] = total - tBal;

        // Send the excess Target back to the user
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
        // Transfer Collect Claims back to the user
        ERC20(claim).safeTransfer(msg.sender, uBal);
        // Burn the user's gclaims
        gclaims[claim].burn(msg.sender, uBal);

        emit Exited(adapter, maturity, msg.sender, uBal);
    }

    /* ========== VIEWS ========== */

    /// @notice Calculates the amount of excess that has accrued since the first Claim from a Series was deposited
    function excess(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) public returns (uint256 tBal) {
        (, address claim, , , , , , , ) = Divider(divider).series(adapter, maturity);
        uint256 initScale = inits[claim];
        uint256 scale = Adapter(adapter).scale();
        uint256 mscale = mscales[claim];
        if (scale <= mscale) {
            scale = mscale;
        } else {
            mscales[claim] = scale;
        }

        if (scale - initScale > 0) {
            tBal = (uBal * scale) / (scale - initScale) / 10**18;
        }
    }

    /* ========== EVENTS ========== */

    event Joined(address indexed adapter, uint48 maturity, address indexed guy, uint256 balance);
    event Exited(address indexed adapter, uint48 maturity, address indexed guy, uint256 balance);
}
