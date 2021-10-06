// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import "solmate/erc20/SafeERC20.sol";
import "./external/DateTime.sol";
import "./external/WadMath.sol";

// Internal references
import "./access/Warded.sol";
import "./libs/errors.sol";
import "./tokens/Claim.sol";
import { BaseFeed as Feed } from "./feed/BaseFeed.sol";
import { Token as Zero } from "./tokens/Token.sol";

/// @title Sense Divider: Divide Assets in Two
/// @author fedealconada + jparklev
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Divider is Warded {
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

    /// @notice Mutable app state
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

    constructor(address _stable, address _cup) Warded() {
        stable = _stable;
        cup = _cup;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Initializes a new Series
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Transfers some fixed amount of stable asset to this contract
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external returns (address zero, address claim) {
        require(feeds[feed], Errors.InvalidFeed);
        require(!_exists(feed, maturity), "Series with given maturity already exists");
        require(_isValid(maturity), "Maturity date is not valid");

        // transfer stable asset balance from msg.sender to this contract
        ERC20(stable).safeTransferFrom(msg.sender, address(this), INIT_STAKE);

        // Strip target
        (zero, claim) = _strip(feed, maturity);

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
        require(_exists(feed, maturity), Errors.SeriesNotExists);
        require(_canBeSettled(feed, maturity), Errors.OutOfWindowBoundaries);

        // Setting the maturity scale value
        series[feed][maturity].mscale = Feed(feed).scale();

        ERC20(Feed(feed).target()).safeTransfer(msg.sender, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(msg.sender, INIT_STAKE);

        emit SeriesSettled(feed, maturity, msg.sender);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Balance of Target to deposit – the amount of Zeros/Claims minted will be the underlying (less fees)
    function issue(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesNotExists);
        require(!_settled(feed, maturity), Errors.IssueOnSettled);

        ERC20 target = ERC20(Feed(feed).target());
        require(target.balanceOf(address(this)) + balance <= guards[address(target)], Errors.GuardCapReached);
        target.safeTransferFrom(msg.sender, address(this), balance);

        uint256 fee = ISSUANCE_FEE.wmul(balance);
        series[feed][maturity].reward += fee;

        // Mint Zero and Claim tokens
        uint256 newBalance = balance - fee;
        uint256 scale = lscales[feed][maturity][msg.sender];
        if (scale == 0) {
            scale = Feed(feed).scale();
            lscales[feed][maturity][msg.sender] = scale;
        }
        uint256 amount = newBalance.wmul(scale);
        Zero(series[feed][maturity].zero).mint(msg.sender, amount);
        Claim(series[feed][maturity].claim).mint(msg.sender, amount);

        emit Issued(feed, maturity, amount, msg.sender);
    }

    /// @notice Burn Zeros and Claims of a specific Series
    /// @dev Burns claims before maturity and also at/after but this is done in the collect() call
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Balance of Zeros and Claims to burn
    function combine(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesNotExists);

        Zero(series[feed][maturity].zero).burn(msg.sender, balance);
        _collect(msg.sender, feed, maturity, balance, address(0));
        if (block.timestamp < maturity) Claim(series[feed][maturity].claim).burn(msg.sender, balance);

        // We use lscale since we have already got the current value on the _collect() call
        uint256 cscale = _settled(feed, maturity) ? series[feed][maturity].mscale : lscales[feed][maturity][msg.sender];
        uint256 tBal = balance.wdiv(cscale);
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);

        emit Combined(feed, maturity, tBal, msg.sender);
    }

    /// @notice Burn Zeros of a Series after maturity
    /// @dev The balance of redeemable Target is a function of the change in Scale
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Amount of Zeros to burn
    function redeemZero(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        // If a Series is settled, we know that it must have existed as well, so we don't need to check that
        require(_settled(feed, maturity), Errors.NotSettled);

        Zero(series[feed][maturity].zero).burn(msg.sender, balance);
        uint256 mscale = series[feed][maturity].mscale;
        uint256 tBal = balance.wdiv(mscale);
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);
        emit Redeemed(feed, maturity, tBal);
    }


    /// @notice Burn Zeros of a Series after maturity
    /// @dev The balance of Fixed Zeros to burn is a function of the change in Scale
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param balance Amount of Zeros to burn
    function redeemClaim(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        // If a Series is settled, we know that it must have existed as well
        require(_settled(feed, maturity), Errors.NotSettled);

        Zero(series[feed][maturity].zero).burn(msg.sender, balance);
        uint256 mscale = series[feed][maturity].mscale;
        uint256 tBal = balance.wdiv(mscale);
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
        require(_exists(feed, maturity), Errors.SeriesNotExists);

        Claim claim = Claim(series[feed][maturity].claim);
        require(claim.balanceOf(usr) >= balance, Errors.NotEnoughClaims);

        uint256 cscale = series[feed][maturity].mscale;
        uint256 lscale = lscales[feed][maturity][usr];

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
    function setFeed(address feed, bool isOn) external onlyWards {
        require(feeds[feed] != isOn, Errors.ExistingValue);
        feeds[feed] = isOn;
        emit FeedChanged(feed, isOn);
    }

    /// @notice Set target's guard
    /// @param target Target address
    /// @param cap The max target that can be deposited on the Divider 
    function setGuard(address target, uint256 cap) external onlyWards {
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
    /// @param scale Value to set as the Series' Scale value at maturity
    /// @param backfills Values to set on lscales mapping
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 mscale,
        Backfill[] memory backfills
    ) external onlyWards {
        require(_exists(feed, maturity), Errors.SeriesNotExists);
        require(mscale > series[feed][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the feed is disabled, it will allow the admin to backfill no matter the maturity
        require(!feeds[feed] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);

        // Set the maturity scale for the Series (important for `redeem` methods)
        series[feed][maturity].mscale = mscale;
        // Set user's last scale values the Series (important for the `collect` method)
        for (uint i = 0; i < backfills.length; i++) {
            lscales[feed][maturity][backfills[i].usr] = backfills[i].lscale;
        }

        // Transfer rewards
        address rewardee = block.timestamp <= maturity + SPONSOR_WINDOW ? series[feed][maturity].sponsor : cup;
        ERC20(Feed(feed).target()).safeTransfer(cup, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(rewardee, INIT_STAKE);

        emit Backfilled(feed, maturity, scale, backfills);
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

    function _strip(address feed, uint256 maturity) internal returns (address zero, address claim) {
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

    event Backfilled(address indexed feed, uint256 indexed maturity, uint256 scale, Backfill[] backfills);
    event Collected(address indexed feed, uint256 indexed maturity, uint256 collected);
    event Combined(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event GuardChanged(address indexed target, uint256 indexed cap);
    event FeedChanged(address indexed feed, bool isOn);
    event Issued(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Redeemed(address indexed feed, uint256 indexed maturity, uint256 redeemed);
    event SeriesInitialized(address indexed feed, uint256 indexed maturity, address zero, address claim, address indexed sponsor);
    event SeriesSettled(address indexed feed, uint256 indexed maturity, address indexed settler);
}
