// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { Yield } from "../tokens/Yield.sol";
import { Token } from "../tokens/Token.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";

/// @title Grounded Yield (gYield)
/// @notice The GYield Manager contract turns Collect Yield into Drag Yield
contract GYieldManager {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice "Issuance" scale value all yields of the same Series must backfill to separated by Yield address
    mapping(address => uint256) public inits;
    /// @notice Total amount of interest collected separated by Yield address
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

        address yield = Divider(divider).yield(adapter, maturity);
        if (yield == address(0)) revert Errors.SeriesDoesNotExist();

        if (address(gyields[yield]) == address(0)) {
            // If this is the first Yield from this Series:
            // * Set the current scale value as the floor
            // * Deploy a new gYield contract

            // NOTE: Because we're transferring Yield in this same TX, we could technically
            // get the scale value from the divider, but that's a little opaque as it relies on side-effects,
            // so i've gone with the clearest solution for now and we can optimize later
            uint256 scale = Adapter(adapter).scale();
            mscales[yield] = scale;
            inits[yield] = scale;
            string memory name = string(abi.encodePacked("G-", ERC20(yield).name(), "-G"));
            string memory symbol = string(abi.encodePacked("G-", ERC20(yield).symbol(), "-G"));
            gyields[yield] = new Token(name, symbol, ERC20(Adapter(adapter).target()).decimals(), address(this));
        } else {
            uint256 tBal = excess(adapter, maturity, uBal);
            if (tBal > 0) {
                // Pull the amount of Target needed to backfill the excess back to issuance
                ERC20(Adapter(adapter).target()).safeTransferFrom(msg.sender, address(this), tBal);
                totals[yield] += tBal;
            }
        }

        // Pull Collect Yield to this contract
        ERC20(yield).safeTransferFrom(msg.sender, address(this), uBal);
        // Mint the user Drag Yield
        gyields[yield].mint(msg.sender, uBal);

        emit Joined(adapter, maturity, msg.sender, uBal);
    }

    function exit(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) external {
        address yield = Divider(divider).yield(adapter, maturity);
        if (yield == address(0)) revert Errors.SeriesDoesNotExist();

        // Collect excess for all Yield from this Series this contract holds
        uint256 collected = Yield(yield).collect();
        // Track the total Target collected manually so that that we don't get
        // mixed up when multiple Series have the same Target
        uint256 total = totals[yield] + collected;

        // Determine how much of stored excess this caller has a right to
        uint256 tBal = uBal.fdiv(gyields[yield].totalSupply(), total);
        totals[yield] = total - tBal;

        // Send the excess Target back to the user
        ERC20(Adapter(adapter).target()).safeTransfer(msg.sender, tBal);
        // Transfer Collect Yield back to the user
        ERC20(yield).safeTransfer(msg.sender, uBal);
        // Burn the user's gyields
        gyields[yield].burn(msg.sender, uBal);

        emit Exited(adapter, maturity, msg.sender, uBal);
    }

    /* ========== VIEWS ========== */

    /// @notice Calculates the amount of excess that has accrued since the first Yield from a Series was deposited
    function excess(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) public returns (uint256 tBal) {
        address yield = Divider(divider).yield(adapter, maturity);
        uint256 initScale = inits[yield];
        uint256 scale = Adapter(adapter).scale();
        uint256 mscale = mscales[yield];
        if (scale <= mscale) {
            scale = mscale;
        } else {
            mscales[yield] = scale;
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
