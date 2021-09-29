// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// external references
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./external/SafeMath.sol";
import "./external/DateTime.sol";
import "./external/WadMath.sol";

// internal references
import "./access/Warded.sol";
import "./libs/errors.sol";
import "./tokens/Claim.sol";
import { BaseFeed as Feed } from "./feed/BaseFeed.sol";
import { BaseToken as Zero } from "./tokens/BaseToken.sol";

// @title Divide tokens in two
// @notice You can use this contract to issue and redeem Sense ERC20 Zeros and Claims
// @dev The implementation of the following function will likely require utility functions and/or libraries,
// the usage thereof is left to the implementer
contract Divider is Warded {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using WadMath for uint256;
    using Errors for string;

    address public stable;
    address public cup;
    uint256 public constant ISSUANCE_FEE = 1; // In percentage (1%). // TODO: TBD
    uint256 public constant INIT_STAKE = 1e18; // Series initialisation stablecoin stake. // TODO: TBD
    uint public constant SPONSOR_WINDOW = 4 hours; // TODO: TBD
    uint public constant SETTLEMENT_WINDOW = 2 hours; // TODO: TBD
    uint public constant MIN_MATURITY = 2 weeks; // TODO: TBD
    uint public constant MAX_MATURITY = 14 weeks; // TODO: TBD

    string private constant ZERO_SYMBOL_PREFIX = "z";
    string private constant ZERO_NAME_PREFIX = "Zero";
    string private constant CLAIM_SYMBOL_PREFIX = "c";
    string private constant CLAIM_NAME_PREFIX = "Claim";

    mapping(address => bool) public feeds;
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

    struct Backfill {
        address usr; // address of the backfilled user
        uint256 scale; // scale value to backfill for usr
    }

    constructor(address _stable, address _cup) Warded() {
        stable = _stable;
        cup = _cup;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // @notice Initializes a new Series
    // @dev Reverts if the feed hasn't been approved or if the Maturity date is invalid
    // @dev Deploys two ERC20 contracts, one for each Zero type
    // @dev Transfers some fixed amount of stable asset to this contract
    // @param feed Feed to associate with the Series
    // @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external returns (address zero, address claim) {
        require(feeds[feed], Errors.InvalidFeed);
        require(!_exists(feed, maturity), "Series with given maturity already exists");

        require(_valid(maturity), "Maturity date is not valid");

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

    // @notice Settles a Series and transfer a settlement reward to the caller
    // @dev The Series' sponsor has a buffer where only they can settle the Series
    // @dev After the buffer, the reward becomes MEV
    // a Series that has matured but hasn't been officially settled yet
    // @param feed Feed to associate with the Series
    // @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        require(!_settled(feed, maturity), Errors.AlreadySettled);
        require(_settable(feed, maturity), Errors.OutOfWindowBoundaries);
        series[feed][maturity].mscale = Feed(feed).scale();
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransfer(msg.sender, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(msg.sender, INIT_STAKE);
        emit SeriesSettled(feed, maturity, msg.sender);
    }

    // @notice Mint Zeros and Claims of a specific Series
    // @dev Pulls Target from the caller and takes the Issuance Fee out of their Zero & Claim share
    // @param feed Feed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Balance of Zeros and Claims to mint the user –
    // the same as the amount of Target they must deposit (less fees)
    function issue(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        require(!_settled(feed, maturity), Errors.IssueOnSettled);
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransferFrom(msg.sender, address(this), balance);
        uint256 fee = ISSUANCE_FEE.mul(balance).div(100);
        series[feed][maturity].reward = series[feed][maturity].reward.add(fee);

        // mint Zero and Claim tokens
        uint256 newBalance = balance.sub(fee);
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

    // @notice Burn Zeros and Claims of a specific Series
    // @dev Reverts if the Series doesn't exist
    // @dev Burns claims before maturity and also at/after but this is done in the collect() call
    // @param feed Feed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Balance of Zeros and Claims to burn
    function combine(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);

        Zero zero = Zero(series[feed][maturity].zero);
        Claim claim = Claim(series[feed][maturity].claim);
        zero.burn(msg.sender, balance);
        _collect(msg.sender, feed, maturity, balance);
        if (block.timestamp < maturity) claim.burn(msg.sender, balance);

        // we use lscale since we have already got the current value on the _collect() call
        uint256 cscale = _settled(feed, maturity) ? series[feed][maturity].mscale : lscales[feed][maturity][msg.sender];
        uint256 tBal = balance.wdiv(cscale);
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);

        emit Combined(feed, maturity, tBal, msg.sender);
    }

    // @notice Burn Zeros of a Series after maturity
    // @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    // @dev Reverts if the series is not settled
    // @dev The balance of Fixed Zeros to burn is a function of the change in Scale
    // @param feed Feed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Amount of Zeros to burn
    function redeemZero(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        require(_settled(feed, maturity), Errors.NotSettled);
        Zero zero = Zero(series[feed][maturity].zero);
        zero.burn(msg.sender, balance);
        uint256 mscale = series[feed][maturity].mscale;
        uint256 tBal = balance.wdiv(mscale);
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);
        emit Redeemed(feed, maturity, tBal);
    }

    // @notice Collect Claim excess before or at/after maturity
    // @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    // @dev Reverts if not called by the Claim contract directly
    // @dev Burns the claim tokens if it's currently at or after maturity as this will be the last possible collect
    // @param usr User who's collecting for their Claims
    // @param feed Feed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Amount of Claim to burn
    function collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 balance
    ) external onlyClaim(feed, maturity) returns (uint256 collected) {
        return _collect(usr,
            feed,
            maturity,
            balance
        );
    }

    function _collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 balance
    ) internal returns (uint256 collected) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        Claim claim = Claim(series[feed][maturity].claim);
        require(claim.balanceOf(usr) >= balance, Errors.NotEnoughClaims);
        uint256 cscale = series[feed][maturity].mscale;
        uint256 lscale = lscales[feed][maturity][usr];
        if (lscale == 0) lscale = series[feed][maturity].iscale;
        if (block.timestamp >= maturity) {
            if (!_settled(feed, maturity)) revert(Errors.CollectNotSettled);
            claim.burn(usr, balance);
        } else {
            if (!_settled(feed, maturity)) {
                cscale = Feed(feed).scale();
                lscales[feed][maturity][usr] = cscale;
            }
        }
        collected = balance.wmul((cscale.sub(lscale)).wdiv(cscale.wmul(lscale)));
        require(collected <= balance.wdiv(lscale), Errors.CapReached); // TODO check this
        ERC20(Feed(feed).target()).safeTransfer(usr, collected);
        emit Collected(feed, maturity, collected);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    // @notice Enable or disable an feed
    // @dev Store the feed address in a registry for easy access on-chain
    // @param feed Feedr's address
    // @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) external onlyWards {
        require(feeds[feed] != isOn, Errors.ExistingValue);
        feeds[feed] = isOn;
        emit FeedChanged(feed, isOn);
    }

    // @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    // @dev Reverts if the Series has already been settled or if the maturity is invalid
    // @dev Reverts if the Scale value is larger than the Scale from issuance, or if its above a certain threshold
    // @param feed Feed's address
    // @param maturity Maturity date for the Series
    // @param scale Value to set as the Series' Scale value at maturity
    // @param backfills Values to set on lscales mapping
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 scale,
        Backfill[] memory backfills
    ) external onlyWards {
        require(_exists(feed, maturity), Errors.NotExists);
        require(scale > series[feed][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity.add(SPONSOR_WINDOW).add(SETTLEMENT_WINDOW);
        // If feed is disabled, it will allow the admin to backfill no matter the maturity.
        require(!feeds[feed] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);
        series[feed][maturity].mscale = scale;
        for (uint i = 0; i < backfills.length; i++) {
            lscales[feed][maturity][backfills[i].usr] = backfills[i].scale;
        }

        // transfer rewards
        address to = block.timestamp <= maturity.add(SPONSOR_WINDOW) ? series[feed][maturity].sponsor : cup;
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransfer(cup, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(to, INIT_STAKE);

        emit Backfilled(feed, maturity, scale, backfills);
    }

    /* ========== INTERNAL & HELPER FUNCTIONS ========== */

    function _exists(address feed, uint256 maturity) internal view returns (bool exists) {
        return address(series[feed][maturity].zero) != address(0);
    }

    function _settled(address feed, uint256 maturity) internal view returns (bool settled) {
        return series[feed][maturity].mscale > 0;
    }

    function _settable(address feed, uint256 maturity) internal view returns (bool exists) {
        bool isSponsor = msg.sender == series[feed][maturity].sponsor;
        uint256 cutoff = maturity.add(SPONSOR_WINDOW).add(SETTLEMENT_WINDOW);
        if (isSponsor && maturity.sub(SPONSOR_WINDOW) <= block.timestamp && block.timestamp <= cutoff) {
            return true;
        }
        if (!isSponsor && maturity.add(SPONSOR_WINDOW) < block.timestamp && block.timestamp <= cutoff) {
            return true;
        }
        return false;
    }

    function _strip(address feed, uint256 maturity) internal returns (address zero, address claim) {
        ERC20 target = ERC20(Feed(feed).target());
        (, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory zname = string(abi.encodePacked(target.name(), " ", datestring, " ", ZERO_NAME_PREFIX, " ", "by Sense"));
        string memory zsymbol = string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring));
        zero = address(new Zero(maturity, address(this), feed, zname, zsymbol));

        string memory cname = string(abi.encodePacked(target.name(), " ", datestring, " ", CLAIM_NAME_PREFIX, " ", "by Sense"));
        string memory csymbol = string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring));
        claim = address(new Claim(maturity, address(this), feed, cname, csymbol));
    }

    function _valid(uint256 maturity) internal view returns (bool valid) {
        if (maturity < block.timestamp + MIN_MATURITY) return false;
        if (maturity > block.timestamp + MAX_MATURITY) return false;

        (, , uint256 day, uint256 hour, uint256 minute, uint256 second) = DateTime.timestampToDateTime(maturity);
        if (day != 1 || hour != 0 || minute != 0 || second != 0) return false;
        return true;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyClaim(address feed, uint256 maturity) {
        address callingContract = address(series[feed][maturity].claim);
        require(callingContract == msg.sender, "Can only be invoked by the Claim contract");
        _;
    }

    /* ========== EVENTS ========== */
    event SeriesInitialized(address indexed feed, uint256 indexed maturity, address zero, address claim, address indexed sponsor);
    event SeriesSettled(address indexed feed, uint256 indexed maturity, address indexed settler);
    event Issued(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Combined(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Backfilled(address indexed feed, uint256 indexed maturity, uint256 scale, Backfill[] backfills);
    event FeedChanged(address indexed feed, bool isOn);
    event Collected(address indexed feed, uint256 indexed maturity, uint256 collected);
    event Redeemed(address indexed feed, uint256 indexed maturity, uint256 redeemed);
}
