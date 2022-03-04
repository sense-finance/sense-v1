// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { YT } from "../tokens/YT.sol";
import { Token } from "../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

/// @title Grounded Yield Tokens (gYTs)
/// @notice The GYT Manager contract turns Collect YTs into Drag YTs
contract GYTManager {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice "Issuance" scale value all YTs of the same Series must backfill to separated by YT address
    mapping(address => uint256) public inits;
    /// @notice Total amount of interest collected separated by YT address
    mapping(address => uint256) public totals;
    /// @notice The max scale value of different Series
    mapping(address => uint256) public mscales;
    mapping(address => Token) public gyields;
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
        if (maturity <= block.timestamp) revert Errors.InvalidMaturity();

        address yt = Divider(divider).yt(adapter, maturity);
        if (yt == address(0)) revert Errors.SeriesDoesNotExist();

        if (address(gyields[yt]) == address(0)) {
            // If this is the first YT from this Series:
            // * Set the current scale value as the floor
            // * Deploy a new gYT contract

            // NOTE: Because we're transferring YT in this same TX, we could technically
            // get the scale value from the divider, but that's a little opaque as it relies on side-effects,
            // so i've gone with the clearest solution for now and we can optimize later
            uint256 scale = Adapter(adapter).scale();
            mscales[yt] = scale;
            inits[yt] = scale;
            string memory name = string(abi.encodePacked("G-", ERC20(yt).name(), "-G"));
            string memory symbol = string(abi.encodePacked("G-", ERC20(yt).symbol(), "-G"));
            gyields[yt] = new Token(name, symbol, ERC20(Adapter(adapter).target()).decimals(), address(this));
        } else {
            uint256 tBal = excess(adapter, maturity, uBal);
            if (tBal > 0) {
                // Pull the amount of Target needed to backfill the excess back to issuance
                ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
                totals[yt] += tBal;
            }
        }

        // Pull Collect YTs to this contract
        ERC20(yt).safeTransferFrom(msg.sender, address(this), uBal);
        // Mint the user Drag YTs
        gyields[yt].mint(msg.sender, uBal);

        emit Joined(adapter, maturity, msg.sender, uBal);
    }

    function exit(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) external {
        address yt = Divider(divider).yt(adapter, maturity);
        if (yt == address(0)) revert Errors.SeriesDoesNotExist();

        // Collect excess for all Yield from this Series this contract holds
        uint256 collected = YT(yt).collect();
        // Track the total Target collected manually so that that we don't get
        // mixed up when multiple Series have the same Target
        uint256 total = totals[yt] + collected;

        // Determine how much of stored excess this caller has a right to
        uint256 tBal = uBal.fdiv(gyields[yt].totalSupply(), total);
        totals[yt] = total - tBal;

        // Send the excess Target back to the user
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        // Transfer Collect YTs back to the user
        ERC20(yt).safeTransfer(msg.sender, uBal);
        // Burn the user's gyields
        gyields[yt].burn(msg.sender, uBal);

        emit Exited(adapter, maturity, msg.sender, uBal);
    }

    /* ========== VIEWS ========== */

    /// @notice Calculates the amount of excess that has accrued since the first YT from a Series was deposited
    function excess(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) public returns (uint256 tBal) {
        address yt = Divider(divider).yt(adapter, maturity);
        uint256 initScale = inits[yt];
        uint256 scale = Adapter(adapter).scale();
        uint256 mscale = mscales[yt];
        if (scale <= mscale) {
            scale = mscale;
        } else {
            mscales[yt] = scale;
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
