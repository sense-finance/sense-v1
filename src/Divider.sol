// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "solmate/erc20/SafeERC20.sol";
import { Trust } from "solmate/auth/Trust.sol";
import { DateTime } from "./external/DateTime.sol";
import { WadMath } from "./external/WadMath.sol";

// Internal references
import { Errors } from "./libs/errors.sol";
import { Claim } from "./tokens/Claim.sol";
import { BaseFeed as Feed } from "./feeds/BaseFeed.sol";
import { Token as Zero } from "./tokens/Token.sol";

/// @title Sense Divider: Divide Assets in Two
/// @author fedealconada + jparklev
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Divider is Trust {
    using SafeERC20 for ERC20;
    using WadMath for uint256;
    using Errors for   string;

    /// @notice Configuration
    uint256 public constant ISSUANCE_FEE = 0.01e18; // In percentage (1%) [WAD] // TODO: TBD
    uint256 public constant INIT_STAKE = 1e18; // Series initialisation stablecoin stake [WAD] // TODO: TBD
    uint256 public constant SPONSOR_WINDOW = 4 hours; // TODO: TBD
    uint256 public constant SETTLEMENT_WINDOW = 2 hours; // TODO: TBD
    uint256 public constant MIN_MATURITY = 2 weeks; // TODO: TBD
    uint256 public constant MAX_MATURITY = 14 weeks; // TODO: TBD

    string private constant ZERO_SYMBOL_PREFIX = "z";
    string private constant ZERO_NAME_PREFIX = "Zero";
    string private constant CLAIM_SYMBOL_PREFIX = "c";
    string private constant CLAIM_NAME_PREFIX = "Claim";

    /// @notice Mutable program state
    address public stable;
    address public    cup;
    mapping(address => bool   ) public feeds;  // feed -> approved 
    mapping(address => uint256) public guards; // target -> max amount of Target allowed to be issued
    mapping(address => mapping(uint256 => Series)) public series; // feed -> maturity -> series
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lscales; // feed -> maturity -> account -> lscale
    struct Series {
        address zero; // Zero address for this Series (deployed on Series initialization)
        address claim; // Claim address for this Series (deployed on Series initialization)
        address sponsor; // Series initializer/sponsor
        uint256 issuance; // Issuance date for this Series (needed for Zero redemption)
        uint256 reward; // Tracks the fees due to the settler on Settlement
        uint256 iscale; // Scale value at issuance
        uint256 mscale; // Scale value at maturity
    }

    constructor(address _stable, address _cup) Trust(msg.sender) {
        stable = _stable;
        cup    = _cup;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Initializes a new Series
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Transfers some fixed amount of stable asset to this contract
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external returns (address zero, address claim) {
        require(feeds[feed], Errors.InvalidFeed);
        require(!_exists(feed, maturity), Errors.DuplicateSeries);
        require(_isValid(maturity), Errors.InvalidMaturity);

        // Transfer stable asset stake from caller to this contract
        ERC20(stable).safeTransferFrom(msg.sender, address(this), INIT_STAKE);

        // Deploy Zeros and Claims for this new Series
        (zero, claim) = _split(feed, maturity);

        // Initialize the new Series struct
        Series memory newSeries = Series({
            zero : zero,
            claim : claim,
            sponsor : msg.sender,
            issuance : block.timestamp,
            reward : 0,
            iscale : Feed(feed).scale(),
            mscale : 0
        });
        series[feed][maturity] = newSeries;

        emit SeriesInitialized(feed, maturity, zero, claim, msg.sender);
    }

    /// @notice Settles a Series and transfer the settlement reward to the caller
    /// @dev The Series' sponsor has a buffer where only they can settle the Series
    /// @dev After the buffer, the reward becomes MEV
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(_canBeSettled(feed, maturity), Errors.OutOfWindowBoundaries);

        // The maturity scale value is all a Series needs for us to consider it "settled"
        series[feed][maturity].mscale = Feed(feed).scale();

        // Reward the caller for doing the work of settling the Series at around the correct time
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(msg.sender, INIT_STAKE);

        emit SeriesSettled(feed, maturity, msg.sender);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit 
    /// the amount of Zeros/Claims minted will be the equivelent value in units of underlying (less fees)
    function issue(address feed, uint256 maturity, uint256 tBal) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(!_settled(feed, maturity), Errors.IssueOnSettled);

        ERC20 target = ERC20(Feed(feed).target());
        // Ensure the caller won't hit the issuance cap with this action
        require(target.balanceOf(address(this)) + tBal <= guards[address(target)], Errors.GuardCapReached);
        target.safeTransferFrom(msg.sender, address(this), tBal);

        // Take the issuance fee out of the deposited Target, and put it towards the settlement reward
        uint256 fee = ISSUANCE_FEE.wmul(tBal);
        series[feed][maturity].reward += fee;
        uint256 tBalSubFee = tBal - fee;
        
        // If the caller has collected on Claims before, use the scale value from that collection to determine how many Zeros/Claims to mint
        // so that the Claims they mint here will have the same amount of yield stored up as their existing holdings
        uint256 scale = lscales[feed][maturity][msg.sender];

        // If the caller has not collected on Claims before, use the current scale value to determine how many Zeros/Claims to mint
        // so that the Claims they mint here are "clean," in that they have no yet-to-be-collected yield
        if (scale == 0) {
            scale = Feed(feed).scale();
            lscales[feed][maturity][msg.sender] = scale;
        }

        // Determine the amount of Underlying equal to the Target being sent in (the principal)
        uint256 uBal = tBalSubFee.wmul(scale);

        // Mint equal amounts of Zeros and Claims 
        Zero(series[feed][maturity].zero  ).mint(msg.sender, uBal);
        Claim(series[feed][maturity].claim).mint(msg.sender, uBal);

        emit Issued(feed, maturity, uBal, msg.sender);
    }

    /// @notice Reconstitute Target by burning Zeros and Claims 
    /// @dev Explicitly burns claims before maturity, and implicitly does it at/after maturity through collect()
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Zeros and Claims to burn
    function combine(address feed, uint256 maturity, uint256 uBal) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);

        Zero(series[feed][maturity].zero).burn(msg.sender, uBal);
        _collect(msg.sender, feed, maturity, uBal, address(0));
        if (block.timestamp < maturity) Claim(series[feed][maturity].claim).burn(msg.sender, uBal);

        // We use lscale since the current scale was already stored there by the _collect() call
        uint256 cscale = _settled(feed, maturity) ? series[feed][maturity].mscale : lscales[feed][maturity][msg.sender];

        // Convert from units of Underlying to units of Target 
        uint256 tBal = uBal.wdiv(cscale);
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);

        emit Combined(feed, maturity, tBal, msg.sender);
    }

    /// @notice Burn Zeros of a Series once its been settled
    /// @dev The balance of redeemable Target is a function of the change in Scale
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Amount of Zeros to burn, which should be equivelent to the amount of Underlying owed to the caller
    function redeemZero(address feed, uint256 maturity, uint256 uBal) external {
        require(feeds[feed], Errors.InvalidFeed);
        // If a Series is settled, we know that it must have existed as well, so that check is unnecessary
        require(_settled(feed, maturity), Errors.NotSettled);
        // Burn the caller's Zeros
        Zero(series[feed][maturity].zero).burn(msg.sender, uBal);

        // Calculate the amount of Target the caller is owed (amount of Target that's 
        // equivelent to their principal in Underlying), then send it them
        uint256 tBal = uBal.wdiv(series[feed][maturity].mscale); // Sensitive to precision loss
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);

        emit Redeemed(feed, maturity, tBal);
    }

    /// @notice Collect Claim excess before, at, or after maturity
    /// @dev Burns the claim tokens if it's currently at or after maturity as this will be the last possible collect
    /// @dev If `to` is set, we copy the lscale value from usr to this address
    /// @param usr User who's collecting for their Claims
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param to address to set the lscale value from usr
    function collect(
        address usr,
        address feed,
        uint256 maturity,
        address to
    ) external onlyClaim(feed, maturity) returns (uint256 collected) {
        return _collect(usr,
            feed,
            maturity,
            Claim(msg.sender).balanceOf(usr),
            to
        );
    }

    function _collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 balance,
        address to
    ) internal returns (uint256 collected) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);

        Claim claim = Claim(series[feed][maturity].claim);
        require(claim.balanceOf(usr) >= balance, Errors.NotEnoughClaims);

        uint256 cscale = series[feed][maturity].mscale;
        uint256 lscale = lscales[feed][maturity][usr];

        // If this is the Claim holder's first time collecting and nobody 
        if (lscale == 0) lscale = series[feed][maturity].iscale;

        if (block.timestamp >= maturity) {
            require(_settled(feed, maturity), Errors.CollectNotSettled);
            claim.burn(usr, balance);
        } else if (!_settled(feed, maturity)) {
            cscale = Feed(feed).scale();
            lscales[feed][maturity][usr] = cscale;
        }

        collected = balance.wdiv(lscale) - balance.wdiv(cscale);
        require(collected <= balance.wdiv(lscale), Errors.CapReached); // TODO check this
        ERC20(Feed(feed).target()).safeTransfer(usr, collected);

        if (to != address(0)) {
            lscales[feed][maturity][to] = cscale;
        }

        emit Collected(feed, maturity, collected);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Enable or disable a feed
    /// @param feed Feed's address
    /// @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) external requiresTrust {
        require(feeds[feed] != isOn, Errors.ExistingValue);
        feeds[feed] = isOn;
        emit FeedChanged(feed, isOn);
    }

    /// @notice Set target's guard
    /// @param target Target address
    /// @param cap The max target that can be deposited on the Divider 
    function setGuard(address target, uint256 cap) external requiresTrust {
        guards[target] = cap;
        emit GuardChanged(target, cap);
    }

    struct Backfill {
        address usr;   // Address of the user who's getting their lscale backfilled
        uint256 lscale; // Scale value to backfill for usr's lscale
    }
    
    /// @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    /// @param feed Feed's address
    /// @param maturity Maturity date for the Series
    /// @param mscale Value to set as the Series' Scale value at maturity
    /// @param backfills Values to set on lscales mapping
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 mscale,
        Backfill[] memory backfills
    ) external requiresTrust {
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(mscale > series[feed][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the feed is disabled, it will allow the admin to backfill no matter the maturity
        require(!feeds[feed] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);

        // Set the maturity scale for the Series (needed for `redeem` methods)
        series[feed][maturity].mscale = mscale;
        // Set user's last scale values the Series (needed for the `collect` method)
        for (uint i = 0; i < backfills.length; i++) {
            lscales[feed][maturity][backfills[i].usr] = backfills[i].lscale;
        }

        // Determine where the rewards should go depending on where we are relative to the maturity date
        address rewardee = block.timestamp <= maturity + SPONSOR_WINDOW ? series[feed][maturity].sponsor : cup;
        ERC20(Feed(feed).target()).safeTransfer(cup, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(rewardee, INIT_STAKE);

        emit Backfilled(feed, maturity, mscale, backfills);
    }

    /* ========== INTERNAL VIEWS ========== */

    function _exists(address feed, uint256 maturity) internal view returns (bool exists) {
        return address(series[feed][maturity].zero) != address(0);
    }

    function _settled(address feed, uint256 maturity) internal view returns (bool settled) {
        return series[feed][maturity].mscale > 0;
    }

    function _canBeSettled(address feed, uint256 maturity) internal view returns (bool canBeSettled) {
        require(!_settled(feed, maturity), Errors.AlreadySettled);
        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the sender is the sponsor for the Series
        if (msg.sender == series[feed][maturity].sponsor) {
            return maturity - SPONSOR_WINDOW <= block.timestamp && cutoff >= block.timestamp;
        } else {
            return maturity + SPONSOR_WINDOW < block.timestamp && cutoff >= block.timestamp;
        }
    }

    function _isValid(uint256 maturity) internal view returns (bool valid) {
        if (maturity < block.timestamp + MIN_MATURITY || maturity > block.timestamp + MAX_MATURITY) return false;

        (, , uint256 day, uint256 hour, uint256 minute, uint256 second) = DateTime.timestampToDateTime(maturity);
        if (day != 1 || hour != 0 || minute != 0 || second != 0) return false;
        return true;
    }

    /* ========== INTERNAL HELPERS ========== */

    function _split(address feed, uint256 maturity) internal returns (address zero, address claim) {
        ERC20 target = ERC20(Feed(feed).target());
        (, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory zname = string(abi.encodePacked(target.name(), " ", datestring, " ", ZERO_NAME_PREFIX, " ", "by Sense"));
        string memory zsymbol = string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring));
        zero = address(new Zero(zname, zsymbol));

        string memory cname = string(abi.encodePacked(target.name(), " ", datestring, " ", CLAIM_NAME_PREFIX, " ", "by Sense"));
        string memory csymbol = string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring));
        claim = address(new Claim(maturity, address(this), feed, cname, csymbol));
    }

    /* ========== MODIFIERS ========== */

    modifier onlyClaim(address feed, uint256 maturity) {
        require(series[feed][maturity].claim == msg.sender, "Can only be invoked by the Claim contract");
        _;
    }

    /* ========== EVENTS ========== */

    event Backfilled(address indexed feed, uint256 indexed maturity, uint256 mscale, Backfill[] backfills);
    event Collected(address indexed feed, uint256 indexed maturity, uint256 collected);
    event Combined(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event GuardChanged(address indexed target, uint256 indexed cap);
    event FeedChanged(address indexed feed, bool isOn);
    event Issued(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Redeemed(address indexed feed, uint256 indexed maturity, uint256 redeemed);
    event SeriesInitialized(address indexed feed, uint256 indexed maturity, address zero, address claim, address indexed sponsor);
    event SeriesSettled(address indexed feed, uint256 indexed maturity, address indexed settler);
}
