// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
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
    using SafeTransferLib for ERC20;
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
        uint256 maturity,
        uint256 uBal
    ) external {
        require(maturity > block.timestamp, Errors.InvalidMaturity);

        Divider.Series memory series = Divider(divider).series(adapter, maturity);
        require(series.claim != address(0), Errors.SeriesDoesntExists);

        if (address(gclaims[series.claim]) == address(0)) {
            // If this is the first Claim from this Series:
            // * Set the current scale value as the floor
            // * Deploy a new gClaim contract

            // NOTE: Because we're transferring Claims in this same TX, we could technically
            // get the scale value from the divider, but that's a little opaque as it relies on side-effects,
            // so i've gone with the clearest solution for now and we can optimize later
            uint256 scale = Adapter(adapter).scale();
            mscales[series.claim] = scale;
            inits[series.claim] = scale;
            string memory name = string(abi.encodePacked("G-", ERC20(series.claim).name(), "-G"));
            string memory symbol = string(abi.encodePacked("G-", ERC20(series.claim).symbol(), "-G"));
            gclaims[series.claim] = new Token(name, symbol, ERC20(Adapter(adapter).target()).decimals(), address(this));
        } else {
            uint256 tBal = excess(adapter, maturity, uBal);
            if (tBal > 0) {
                // Pull the amount of Target needed to backfill the excess back to issuance
                ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
                totals[series.claim] += tBal;
            }
        }

        // Pull Collect Claims to this contract
        ERC20(series.claim).safeTransferFrom(msg.sender, address(this), uBal);
        // Mint the user Drag Claims
        gclaims[series.claim].mint(msg.sender, uBal);

        emit Joined(adapter, maturity, msg.sender, uBal);
    }

    function exit(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) external {
        Divider.Series memory series = Divider(divider).series(adapter, maturity);

        require(series.claim != address(0), Errors.SeriesDoesntExists);

        // Collect excess for all Claims from this Series this contract holds
        uint256 collected = Claim(series.claim).collect();
        // Track the total Target collected manually so that that we don't get
        // mixed up when multiple Series have the same Target
        uint256 total = totals[series.claim] + collected;

        // Determine how much of stored excess this caller has a right to
        uint256 tBal = uBal.fdiv(gclaims[series.claim].totalSupply(), total);
        totals[series.claim] = total - tBal;

        // Send the excess Target back to the user
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        // Transfer Collect Claims back to the user
        ERC20(series.claim).safeTransfer(msg.sender, uBal);
        // Burn the user's gclaims
        gclaims[series.claim].burn(msg.sender, uBal);

        emit Exited(adapter, maturity, msg.sender, uBal);
    }

    /* ========== VIEWS ========== */

    /// @notice Calculates the amount of excess that has accrued since the first Claim from a Series was deposited
    function excess(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) public returns (uint256 tBal) {
        Divider.Series memory series = Divider(divider).series(adapter, maturity);
        uint256 initScale = inits[series.claim];
        uint256 scale = Adapter(adapter).scale();
        uint256 mscale = mscales[series.claim];
        if (scale <= mscale) {
            scale = mscale;
        } else {
            mscales[series.claim] = scale;
        }

        if (scale - initScale > 0) {
            tBal = ((uBal.fmul(scale, FixedMath.WAD)).fdiv(scale - initScale, FixedMath.WAD)).fdivUp(
                10**18,
                FixedMath.WAD
            );
        }
    }

    /* ========== EVENTS ========== */

    event Joined(address indexed adapter, uint256 maturity, address indexed guy, uint256 balance);
    event Exited(address indexed adapter, uint256 maturity, address indexed guy, uint256 balance);
}
