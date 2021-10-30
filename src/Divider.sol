// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { DateTime } from "./external/DateTime.sol";
import { FixedMath } from "./external/FixedMath.sol";

// Internal references
import { Errors } from "./libs/Errors.sol";
import { Claim } from "./tokens/Claim.sol";
import { BaseFeed as Feed } from "./feeds/BaseFeed.sol";
import { Token as Zero } from "./tokens/Token.sol";
import { BaseTWrapper } from "./wrappers/BaseTWrapper.sol";

/// @title Sense Divider: Divide Assets in Two
/// @author fedealconada + jparklev
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Divider is Trust {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;
    using Errors for string;

    /// @notice Configuration
    uint256 public constant SPONSOR_WINDOW = 4 hours; // TODO: TBD
    uint256 public constant SETTLEMENT_WINDOW = 2 hours; // TODO: TBD

    /// @notice Program state
    address public periphery;
    address public immutable cup;
    address public immutable deployer;
    bool public permissionless;
    uint256 public feedCounter;

    /// @notice feed -> is supported
    mapping(address => bool) public feeds;
    /// @notice feed ID -> feed address
    mapping(uint256 => address) public feedAddresses;
    /// @notice feed address -> feed ID
    mapping(address => uint256) public feedIDs;
    /// @notice target -> max amount of Target allowed to be issued
    mapping(address => uint256) public guards;
    /// @notice feed -> maturity -> Series
    mapping(address => mapping(uint256 => Series)) public series;
    /// @notice feed -> maturity -> user -> lscale
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lscales;

    struct Series {
        address zero;
        address claim;
        address sponsor;
        uint256 issuance;
        uint256 reward; // tracks fees due to the series' settler
        uint256 iscale; // scale at issuance
        uint256 mscale; // scale at maturity
        uint256 maxscale; // max scale value from this series' lifetime
        uint256 tilt; // % of underlying principal initially reserved for Claims
    }

    constructor(address _cup, address _deployer) Trust(msg.sender) {
        cup      = _cup;
        deployer = _deployer;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Enable a feed
    /// @param feed Feed's address
    function addFeed(address feed) external whenPermissionless {
        _setFeed(feed, true);
    }

    /// @notice Initializes a new Series
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Transfers some fixed amount of stake asset to this contract
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity, address sponsor) external onlyPeriphery returns (address zero, address claim) {
        require(feeds[feed], Errors.InvalidFeed);
        require(!_exists(feed, maturity), Errors.DuplicateSeries);
        require(_isValid(feed, maturity), Errors.InvalidMaturity);

        // Transfer stake asset stake from caller to this contract
        ERC20 stake = ERC20(Feed(feed).stake());
        ERC20(stake).safeTransferFrom(msg.sender, address(this), Feed(feed).initStake() / _convertBase(stake.decimals()));

        // Deploy Zeros and Claims for this new Series
        (zero, claim) = AssetDeployer(deployer).deploy(feed, maturity);

        // Initialize the new Series struct
        Series memory newSeries = Series({
            zero : zero,
            claim : claim,
            sponsor : sponsor,
            issuance : block.timestamp,
            reward : 0,
            iscale : Feed(feed).scale(),
            mscale : 0,
            maxscale : Feed(feed).scale(),
            tilt : Feed(feed).tilt()
        });

        series[feed][maturity] = newSeries;

        emit SeriesInitialized(feed, maturity, zero, claim, sponsor, Feed(feed).target());
    }

    /// @notice Settles a Series and transfer the settlement reward to the caller
    /// @dev The Series' sponsor has a buffer where only they can settle the Series
    /// @dev After that, the reward becomes MEV
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) external {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(_canBeSettled(feed, maturity), Errors.OutOfWindowBoundaries);

        // The maturity scale value is all a Series needs for us to consider it "settled"
        uint256 mscale = Feed(feed).scale();
        series[feed][maturity].mscale = mscale;

        if (mscale > series[feed][maturity].maxscale) {
            series[feed][maturity].maxscale = mscale;
        }

        // Reward the caller for doing the work of settling the Series at around the correct time
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransfer(msg.sender, series[feed][maturity].reward);

        ERC20 stake = ERC20(Feed(feed).stake());
        ERC20(stake).safeTransfer(msg.sender, Feed(feed).initStake() / _convertBase(ERC20(stake).decimals()));

        emit SeriesSettled(feed, maturity, msg.sender);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit
    /// @dev The balance of Zeros/Claims minted will be the same value in units of underlying (less fees)
    function issue(address feed, uint256 maturity, uint256 tBal) external returns (uint256 uBal) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(!_settled(feed, maturity), Errors.IssueOnSettled);

        ERC20 target = ERC20(Feed(feed).target());
        uint256 tDecimals = target.decimals();
        uint256 tBase = 10 ** tDecimals;
        uint256 fee;

        // Take the issuance fee out of the deposited Target, and put it towards the settlement reward
        uint256 issuanceFee = Feed(feed).issuanceFee();
        if (tDecimals != 18) {
            fee = (tDecimals < 18 ? issuanceFee / (10**(18 - tDecimals)) : issuanceFee * 10**(tDecimals - 18)).fmul(tBal, tBase);
        } else {
            fee = issuanceFee.fmul(tBal, tBase);
        }

        series[feed][maturity].reward += fee;
        uint256 tBalSubFee = tBal - fee;

        // Ensure the caller won't hit the issuance cap with this action
        require(target.balanceOf(address(this)) + tBal <= guards[address(target)], Errors.GuardCapReached);
        target.safeTransferFrom(msg.sender, Feed(feed).twrapper(), tBalSubFee);
        target.safeTransferFrom(msg.sender, address(this), fee); // we keep fees on divider

        // Update values on target wrapper
        BaseTWrapper(Feed(feed).twrapper()).join(msg.sender, tBalSubFee);

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
        uBal = tBalSubFee.fmul(scale, Zero(series[feed][maturity].zero).BASE_UNIT());

        // Mint equal amounts of Zeros and Claims
        Zero(series[feed][maturity].zero  ).mint(msg.sender, uBal);
        Claim(series[feed][maturity].claim).mint(msg.sender, uBal);

        emit Issued(feed, maturity, uBal, msg.sender);
    }

    /// @notice Reconstitute Target by burning Zeros and Claims
    /// @dev Explicitly burns claims before maturity, and implicitly does it at/after maturity through `_collect()`
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Zeros and Claims to burn
    function combine(address feed, uint256 maturity, uint256 uBal) external returns (uint256 tBal) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);

        // Burn the Zeros
        Zero(series[feed][maturity].zero).burn(msg.sender, uBal);
        // Collect whatever excess is due
        _collect(msg.sender, feed, maturity, uBal, uBal, address(0));

        // We use lscale since the current scale was already stored there in `_collect()`
        uint256 cscale = series[feed][maturity].mscale;
        if (!_settled(feed, maturity)) {
            // If it's not settled, then Claims won't be burned automatically in `_collect()`
            Claim(series[feed][maturity].claim).burn(msg.sender, uBal);
            cscale = lscales[feed][maturity][msg.sender];
        }

        // Convert from units of Underlying to units of Target
        tBal = uBal.fdiv(cscale, 10**ERC20(Feed(feed).target()).decimals());
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransferFrom(Feed(feed).twrapper(), msg.sender, tBal);
        BaseTWrapper(Feed(feed).twrapper()).exit(msg.sender, tBal); // distribute reward tokens

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

        // Amount of Target Zeros would ideally have
        uint256 tBal = uBal.fdiv(series[feed][maturity].mscale, 10 ** ERC20(Feed(feed).target()).decimals())
            .fmul(FixedMath.WAD - series[feed][maturity].tilt, 10 ** ERC20(Feed(feed).target()).decimals());

        if (series[feed][maturity].mscale < series[feed][maturity].maxscale) {
            // Amount of Target we actually have set aside for them (after collections from Claim holders)
            uint256 tBalZeroActual = uBal.fdiv(series[feed][maturity].maxscale, 10 ** ERC20(Feed(feed).target()).decimals())
                .fmul(FixedMath.WAD - series[feed][maturity].tilt, 10 ** ERC20(Feed(feed).target()).decimals());

            // Set our Target transfer value to the actual principal we have reserved for Zeros
            tBal = tBalZeroActual;

            // How much principal we have set aside for Claim holders
            uint256 tBalClaimActual = tBalZeroActual.fmul(series[feed][maturity].tilt, 10 ** ERC20(Feed(feed).target()).decimals());

            // Cut from Claim holders to cover shortfall if we can
            if (tBalClaimActual != 0) {
                uint256 shortfall = tBal - tBalZeroActual;
                // If the shortfall is less than what we've reserved for Claims, cover the whole thing
                // (accounting for what the Claim holders will be able to redeem is done in the redeemClaims method)
                if (tBalClaimActual > shortfall) {
                    tBal += shortfall;
                // If the shortfall is greater than what we've reserved for Claims, take as much as we can
                } else {
                    tBal += tBalClaimActual;
                }
            }
        }

        ERC20(Feed(feed).target()).safeTransferFrom(Feed(feed).twrapper(), msg.sender, tBal);
        BaseTWrapper(Feed(feed).twrapper()).exit(msg.sender, tBal);
        emit ZeroRedeemed(feed, maturity, tBal);
    }

    function collect(
        address usr, address feed, uint256 maturity, uint256 uBalTransfer, address to
    ) external onlyClaim(feed, maturity) returns (uint256 collected) {
        uint256 uBal = Claim(msg.sender).balanceOf(usr);
        return _collect(usr,
            feed,
            maturity,
            uBal,
            uBalTransfer > 0 ? uBalTransfer : uBal,
            to
        );
    }

    /// @notice Collect Claim excess before, at, or after maturity
    /// @dev If `to` is set, we copy the lscale value from usr to this address
    /// @param usr User who's collecting for their Claims
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal claim balance
    /// @param uBalTransfer original transfer value
    /// @param to address to set the lscale value from usr
    function _collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 uBal,
        uint256 uBalTransfer,
        address to
    ) internal returns (uint256 collected) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);

        Series memory _series = series[feed][maturity];

        // Get the scale value from the last time this holder collected (default to maturity)
        uint256 lscale = lscales[feed][maturity][usr];
        Claim claim = Claim(series[feed][maturity].claim);
        ERC20 target = ERC20(Feed(feed).target());

        // If this is the Claim holder's first time collecting and nobody sent these Claims to them,
        // set the "last scale" value to the scale at issuance for this series
        if (lscale == 0) lscale = _series.iscale;

        // If the Series has been settled, this should be their last collect, so redeem the users claims for them
        if (_settled(feed, maturity)) {
            _redeemClaim(usr, feed, maturity, uBal);
        } else {
            // If we're not settled and we're past maturity + the sponsor window,
            // anyone can settle this Series so revert until someone does
            if (block.timestamp > maturity + SPONSOR_WINDOW) {
                revert(Errors.CollectNotSettled);
            // Otherwise, this is a valid pre-settlement collect and we need to determine the scale value
            } else {
                uint256 cscale = Feed(feed).scale();
                // If this is larger than the largest scale we've seen for this Series, use it
                if (cscale > _series.maxscale) {
                    _series.maxscale = cscale;
                    lscales[feed][maturity][usr] = cscale;
                // If not, use the previously noted max scale value
                } else {
                    lscales[feed][maturity][usr] = _series.maxscale;
                }
            }
        }

        // Determine how much underlying has accrued since the last time this user collected, in units of Target.
        // (Or take the last time as issuance if they haven't yet)
        //
        // Reminder: `Underlying / Scale = Target`
        // So the following equation is saying, for some amount of Underlying `u`:
        // "Balance of Target that equaled `u` at the last collection _minus_ Target that equals `u` now"
        //
        // Because maxscale must be increasing, the Target balance needed to equal `u` decreases, and that "excess"
        // is what Claim holders are collecting
        uint256 tBalNow = uBal.fdiv(_series.maxscale, claim.BASE_UNIT());
        collected = uBal.fdiv(lscale, claim.BASE_UNIT()) - tBalNow;
        target.safeTransferFrom(Feed(feed).twrapper(), usr, collected);
        BaseTWrapper(Feed(feed).twrapper()).exit(usr, collected); // distribute reward tokens

        // If this collect is a part of a token transfer to another address, set the receiver's
        // last collection to this scale (as all yield is being stripped off before the Claims are sent)
        if (to != address(0)) {
            lscales[feed][maturity][to] = _series.maxscale;
            uint tBalTransfer = uBalTransfer.fdiv(_series.maxscale, claim.BASE_UNIT());
            BaseTWrapper(Feed(feed).twrapper()).exit(usr, tBalTransfer);
            BaseTWrapper(Feed(feed).twrapper()).join(to, tBalTransfer);
        }

        emit Collected(feed, maturity, collected);
    }

    function _redeemClaim(address usr, address feed, uint256 maturity, uint256 uBal) internal {
        require(feeds[feed], Errors.InvalidFeed);
        // If a Series is settled, we know that it must have existed as well, so that check is unnecessary
        require(_settled(feed, maturity), Errors.NotSettled);

        Series memory _series = series[feed][maturity];

        // Burn the users's Claims
        Claim(_series.claim).burn(usr, uBal);

        uint256 tBal = 0;
        // If there's some principal set aside for Claims, determine whether they get it all
        if (_series.tilt != 0) {
            // Amount of Target we have set aside for Claims (Target * % set aside for Claims)
            tBal = uBal.fdiv(_series.maxscale, 10 ** ERC20(Feed(feed).target()).decimals())
                .fmul(_series.tilt, 10 ** ERC20(Feed(feed).target()).decimals());

            // If is down relative to its max, we'll try to take the shortfall out of Claim's principal
            if (_series.mscale < _series.maxscale) {
                // Amount of Target we would ideally have set aside for Zero holders
                uint256 tBalZeroIdeal = uBal.fdiv(_series.mscale, 10 ** ERC20(Feed(feed).target()).decimals())
                    .fmul(FixedMath.WAD - _series.tilt, 10 ** ERC20(Feed(feed).target()).decimals());

                // Amount of Target we actually have set aside for them (after collections from Claim holders)
                uint256 tBalZeroActual = uBal.fdiv(_series.maxscale, 10 ** ERC20(Feed(feed).target()).decimals())
                    .fmul(FixedMath.WAD - _series.tilt, 10 ** ERC20(Feed(feed).target()).decimals());

                // Calculate how much is getting taken from Claim's principal
                uint256 shortfall = tBalZeroIdeal - tBalZeroActual;

                // If the shortfall is less than what we've reserved for Claims, cover the whole thing
                // (accounting for what the Claim holders will be able to redeem is done in the redeemClaims method)
                if (tBal > shortfall) {
                    tBal -= shortfall;
                // If the shortfall is greater than what we've reserved for Claims, take as much as we can
                } else {
                    tBal = 0;
                }
            }
            ERC20(Feed(feed).target()).safeTransferFrom(Feed(feed).twrapper(), usr, tBal);
            BaseTWrapper(Feed(feed).twrapper()).exit(usr, tBal);
        }

        emit ClaimRedeemed(feed, maturity, tBal);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Enable or disable a feed
    /// @param feed Feed's address
    /// @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) public requiresTrust {
        _setFeed(feed, isOn);
    }

    /// @notice Set target's guard
    /// @param target Target address
    /// @param cap The max target that can be deposited on the Divider
    function setGuard(address target, uint256 cap) external requiresTrust {
        guards[target] = cap;
        emit GuardChanged(target, cap);
    }

    /// @notice Set periphery's contract
    /// @param _periphery Target address
    function setPeriphery(address _periphery) external requiresTrust {
        periphery = _periphery;
        emit PeripheryChanged(periphery);
    }

    /// @notice Set permissioless mode
    /// @param _permissionless bool
    function setPermissionless(bool _permissionless) external requiresTrust {
        permissionless = _permissionless;
        emit PermissionlessChanged(permissionless);
    }

    /// @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    /// @param feed Feed's address
    /// @param maturity Maturity date for the Series
    /// @param mscale Value to set as the Series' Scale value at maturity
    /// @param _usrs Values to set on lscales mapping
    /// @param _lscales Values to set on lscales mapping
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 mscale,
        address[] calldata _usrs,
        uint256[] calldata _lscales
    ) external requiresTrust {
        require(_exists(feed, maturity), Errors.SeriesDoesntExists);
        require(mscale > series[feed][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the feed is disabled, it will allow the admin to backfill no matter the maturity
        require(!feeds[feed] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);

        // Set the maturity scale for the Series (needed for `redeem` methods)
        series[feed][maturity].mscale = mscale;
        if (mscale > series[feed][maturity].maxscale) {
            series[feed][maturity].maxscale = mscale;
        }
        // Set user's last scale values the Series (needed for the `collect` method)
        for (uint i = 0; i < _usrs.length; i++) {
            lscales[feed][maturity][_usrs[i]] = _lscales[i];
        }

        // Determine where the rewards should go depending on where we are relative to the maturity date
        address rewardee = block.timestamp <= maturity + SPONSOR_WINDOW ? series[feed][maturity].sponsor : cup;
        ERC20 target = ERC20(Feed(feed).target());
        target.safeTransfer(cup, series[feed][maturity].reward);
        ERC20 stake = ERC20(Feed(feed).stake());
        ERC20(stake).safeTransfer(rewardee, Feed(feed).initStake() / _convertBase(ERC20(stake).decimals()));

        emit Backfilled(feed, maturity, mscale, _usrs, _lscales);
    }

    /// @notice Allows admin to withdraw the reward (airdropped) tokens accrued from fees
    /// @param feed Feed's address
    function withdrawFeesRewards(address feed) external requiresTrust {
        ERC20 rewardToken = ERC20(BaseTWrapper(Feed(feed).twrapper()).reward());
        rewardToken.safeTransfer(cup, rewardToken.balanceOf(address(this)));
    }

    /* ========== INTERNAL VIEWS ========== */

    function _exists(address feed, uint256 maturity) internal view returns (bool) {
        return series[feed][maturity].zero != address(0);
    }

    function _settled(address feed, uint256 maturity) internal view returns (bool) {
        return series[feed][maturity].mscale > 0;
    }

    function _canBeSettled(address feed, uint256 maturity) internal view returns (bool) {
        require(!_settled(feed, maturity), Errors.AlreadySettled);
        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the sender is the sponsor for the Series
        if (msg.sender == series[feed][maturity].sponsor) {
            return maturity - SPONSOR_WINDOW <= block.timestamp && cutoff >= block.timestamp;
        } else {
            return maturity + SPONSOR_WINDOW < block.timestamp && cutoff >= block.timestamp;
        }
    }

    function _isValid(address feed, uint256 maturity) internal view returns (bool) {
        if (maturity < block.timestamp + Feed(feed).minMaturity() || maturity > block.timestamp + Feed(feed).maxMaturity()) return false;

        (, , uint256 day, uint256 hour, uint256 minute, uint256 second) = DateTime.timestampToDateTime(maturity);
        if (day != 1 || hour != 0 || minute != 0 || second != 0) return false;
        return true;
    }

    /* ========== INTERNAL FNCTIONS & HELPERS ========== */
    function _setFeed(address feed, bool isOn) internal {
        require(feeds[feed] != isOn, Errors.ExistingValue);
        feeds[feed] = isOn;
        if (isOn) {
            feedAddresses[feedCounter] = feed;
            feedIDs[feedCounter++] = feed;
        }
        emit FeedChanged(feed, feedCounter, isOn);
    }

    function _convertBase(uint256 decimals) internal pure returns (uint256) {
        if (decimals == 18) return 1;
        return decimals > 18 ? 10 ** (decimals - 18) : 10 ** (18 - decimals);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyClaim(address feed, uint256 maturity) {
        require(series[feed][maturity].claim == msg.sender, "Can only be invoked by the Claim contract");
        _;
    }

    modifier onlyPeriphery() {
        require(periphery == msg.sender, "Can only be invoked by the Periphery contract");
        _;
    }

    modifier whenPermissionless() {
        require(permissionless, Errors.OnlyPermissionless);
        _;
    }

    /* ========== EVENTS ========== */

    /// @notice Admin
    event Backfilled(
        address indexed feed,
        uint256 indexed maturity,
        uint256 mscale,
        address[] _usrs,
        uint256[] _lscales
    );
    event GuardChanged(address indexed target, uint256 indexed cap);
    event FeedChanged(address indexed feed, uint256 indexed id, bool isOn);
    event PeripheryChanged(address indexed periphery);

    /// @notice Series lifecycle
    /// *---- beginning
    event SeriesInitialized(
        address feed,
        uint256 indexed maturity,
        address zero,
        address claim,
        address indexed sponsor,
        address indexed target
    );
    /// -***- middle
    event Issued(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Combined(address indexed feed, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Collected(address indexed feed, uint256 indexed maturity, uint256 collected);
    /// ----* end
    event SeriesSettled(address indexed feed, uint256 indexed maturity, address indexed settler);
    event ZeroRedeemed(address indexed feed, uint256 indexed maturity, uint256 redeemed);
    event ClaimRedeemed(address indexed feed, uint256 indexed maturity, uint256 redeemed);
    /// *----* misc
    event PermissionlessChanged(bool indexed permissionless);

}

contract AssetDeployer is Trust {
    /// @notice Configuration
    string private constant ZERO_SYMBOL_PREFIX = "z";
    string private constant ZERO_NAME_PREFIX = "Zero";
    string private constant CLAIM_SYMBOL_PREFIX = "c";
    string private constant CLAIM_NAME_PREFIX = "Claim";

    /// @notice Program state
    bool public inited;
    address public divider;

    constructor() Trust(msg.sender) { }
    function init(address _divider) external requiresTrust {
        require(!inited, "Already initialized");
        divider = _divider;
        inited = true;
    }

    function deploy(address feed, uint256 maturity) external returns (address zero, address claim) {
        require(inited, "Not yet initialized");
        require(msg.sender == divider, "Must be called by the Divider");

        ERC20 target = ERC20(Feed(feed).target());
        uint8 decimals = target.decimals();
        string memory name = target.name();
        (, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory feedId = uint2str(Divider(divider).feedIDs(feed));
        zero = address(new Zero(
            string(abi.encodePacked(name, " ", datestring, " ", ZERO_NAME_PREFIX, " #", feedId, " by Sense")),
            string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", feedId)),
            decimals,
            divider
        ));

        claim = address(new Claim(
            maturity,
            divider,
            feed,
            string(abi.encodePacked(name, " ", datestring, " ", CLAIM_NAME_PREFIX, " #", feedId, " by Sense")),
            string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", feedId)),
            decimals
        ));
    }

    /// Taken from https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
    /// @dev modified to be compatible with 0.8
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}