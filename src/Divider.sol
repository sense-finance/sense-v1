pragma solidity ^0.8.6;

// Internal references
import "./interfaces/IDivider.sol";
import "./interfaces/IFeed.sol";
import "./tokens/Zero.sol";
import "./tokens/Claim.sol";
import "./libs/errors.sol";

// External references
import "./external/SafeMath.sol";
import "./external/DateTime.sol";
import "./external/WadMath.sol";
import "./external/tokens/SafeERC20.sol";

// @title Divide tokens in two
// @notice You can use this contract to issue and redeem Sense ERC20 Zeros and Claims
// @dev The implementation of the following function will likely require utility functions and/or libraries,
// the usage thereof is left to the implementer
contract Divider is IDivider {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using WadMath for uint256;
    using Errors for string;

    address public stable;
    address public multisig;
    uint256 public constant ISSUANCE_FEE = 1; // In percentage (1%). // TODO: TBD
    uint256 public constant INIT_STAKE = 1e18; // Series initialisation stablecoin stake. // TODO: TBD
    uint public constant SPONSOR_WINDOW = 4 hours; // TODO: TBD
    uint public constant SETTLEMENT_WINDOW = 2 hours; // TODO: TBD
    uint public constant MIN_MATURITY = 2 weeks; // TODO: TBD
    uint public constant MAX_MATURITY = 14 weeks; // TODO: TBD

    bytes32 private constant ZERO_SYMBOL_PREFIX = "z";
    bytes32 private constant ZERO_NAME_PREFIX = "Zero";
    bytes32 private constant CLAIM_SYMBOL_PREFIX = "c";
    bytes32 private constant CLAIM_NAME_PREFIX = "Claim";

    mapping(address => uint256) public wards;
    mapping(address => bool) public feeds;
    mapping(address => mapping(uint256 => Series)) public series; // feed -> maturity -> series
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lscales; // feed -> maturity -> account -> lScale

    struct Series {
        address zero; // Zero address for this Series (deployed on Series initialization)
        address claim; // Claim address for this Series (deployed on Series initialization)
        address sponsor; // Series initializer/sponsor
        uint256 issuance; // Issuance date for this Series (needed for Zero redemption)
        uint256 reward; // Tracks the fees due to the settler on Settlement
        uint256 iscale; // Scale value at issuance
        uint256 mscale; // Scale value at maturity
    }

    constructor(address govAddress, address _stable, address _multisig) {
        wards[govAddress] = 1;
        stable = _stable;
        multisig = _multisig;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // @notice Initializes a new Series
    // @dev Reverts if the feed hasn't been approved or if the Maturity date is invalid
    // @dev Deploys two ERC20 contracts, one for each Zero type
    // @dev Transfers some fixed amount of stable asset to this contract
    // @param feed IFeed to associate with the Series
    // @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external override returns (address zero, address claim) {
        require(ERC20(stable).allowance(msg.sender, address(this)) >= INIT_STAKE, "Allowance not high enough");
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
            iscale : IFeed(feed).scale(),
            mscale : 0
        });
        series[feed][maturity] = newSeries;
        emit SeriesInitialised(zero, claim, msg.sender);
    }

    // @notice Settles a Series and transfer a settlement reward to the caller
    // @dev The Series' sponsor has a buffer where only they can settle the Series
    // @dev After the buffer, the reward becomes MEV
    // a Series that has matured but hasn't been officially settled yet
    // @param feed IFeed to associate with the Series
    // @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) external override {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        require(!_settled(feed, maturity), Errors.AlreadySettled);
        require(_settable(feed, maturity), Errors.OutOfWindowBoundaries);
        series[feed][maturity].mscale = IFeed(feed).scale();
        ERC20 target = ERC20(IFeed(feed).target());
        target.safeTransfer(msg.sender, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(msg.sender, INIT_STAKE);
        emit SeriesSettled(feed, maturity, msg.sender);
    }

    // @notice Mint Zeros and Claims of a specific Series
    // @dev Pulls Target from the caller and takes the Issuance Fee out of their Zero & Claim share
    // @param feed IFeed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Balance of Zeros and Claims to mint the user –
    // the same as the amount of Target they must deposit (less fees)
    function issue(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        ERC20 target = ERC20(IFeed(feed).target());
        require(target.allowance(msg.sender, address(this)) >= balance, Errors.AllowanceNotEnough);
        target.safeTransferFrom(msg.sender, address(this), balance);
        uint256 fee = ISSUANCE_FEE.mul(balance).div(100);
        series[feed][maturity].reward = series[feed][maturity].reward.add(fee);

        // mint Zero and Claim tokens
        uint256 newBalance = balance.sub(fee);
        uint256 scale = series[feed][maturity].mscale;
        if (!_settled(feed, maturity)) {
            scale = lscales[feed][maturity][msg.sender];
            if (scale == 0) {
                scale = IFeed(feed).scale();
                lscales[feed][maturity][msg.sender] = scale;
            }
        }
        uint256 amount = newBalance.wmul(scale);
        Zero(series[feed][maturity].zero).mint(msg.sender, amount);
        Claim(series[feed][maturity].claim).mint(msg.sender, amount);

        emit Issued(feed, maturity, amount, msg.sender);
    }

    // @notice Burn Zeros and Claims of a specific Series
    // @dev Reverts if the Series doesn't exist
    // @param feed Feed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Balance of Zeros and Claims to burn
    function combine(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        Zero zero = Zero(series[feed][maturity].zero);
        Claim claim = Claim(series[feed][maturity].claim);
        zero.burn(msg.sender, balance);
        claim.burn(msg.sender, balance);

        uint256 cscale = series[feed][maturity].mscale;
        if (!_settled(feed, maturity)) {
            cscale = lscales[feed][maturity][msg.sender];
        }

        uint256 tBal = balance.wdiv(cscale);
        ERC20(IFeed(feed).target()).safeTransfer(msg.sender, tBal);
        emit Combined(feed, maturity, tBal, msg.sender);
    }

    // @notice Burn Zeros of a Series after maturity
    // @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    // @dev Reverts if the series is not settled
    // @dev The balance of Fixed Zeros to burn is a function of the change in Scale
    // @param feed IFeed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Amount of Zeros to burn
    function redeemZero(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);
        require(balance > 0, Errors.ZeroBalance);
        require(_settled(feed, maturity), Errors.NotSettled);
        Zero zero = Zero(series[feed][maturity].zero);
//        uint256 b = zero.balanceOf(msg.sender);
//        require(b >= balance, Errors.NotSettled);
        zero.burn(msg.sender, balance);
        uint256 mscale = series[feed][maturity].mscale;
        uint256 tBal = balance.wdiv(mscale);
        require(tBal <= balance.wdiv(mscale), Errors.CapReached);
        ERC20(IFeed(feed).target()).safeTransfer(msg.sender, tBal);
        emit Redeemed(feed, maturity, tBal);
    }

    // @notice Collect Claim excess before or at/after maturity
    // @dev Reverts if the maturity date is invalid or if the Series doesn't exist
    // @dev Reverts if not called by the Claim contract directly
    // @dev Burns the claim tokens if it's currently at or after maturity as this will be the last possible collect
    // @param usr User who's collecting for their Claims
    // @param feed IFeed address for the Series
    // @param maturity Maturity date for the Series
    // @param balance Amount of Claim to burn
    function collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 balance
    ) external override onlyClaim(feed, maturity) returns (uint256 collected) {
        require(feeds[feed], Errors.InvalidFeed);
        require(_exists(feed, maturity), Errors.NotExists);

        bool burn = false;
        uint256 cscale = series[feed][maturity].mscale;
        uint256 lScale = lscales[feed][maturity][usr];
        Claim claim = Claim(series[feed][maturity].claim);
        if (lScale == 0) lScale = series[feed][maturity].iscale;
        if (block.timestamp >= maturity) {
            if (!_settled(feed, maturity)) revert(Errors.CollectNotSettled);
            burn = true;
        } else {
            if (!_settled(feed, maturity)) {
                cscale = IFeed(feed).scale();
                lscales[feed][maturity][usr] = cscale;
            }
        }

        require(claim.balanceOf(usr) >= balance, "Not enough claims to collect given target balance");
        collected = balance.wmul((cscale.sub(lScale)).wdiv(cscale.wmul(lScale)));
        require(collected <= balance.wdiv(lScale), Errors.CapReached); // TODO check this
        if (burn) {
            claim.burn(usr, balance, false);
            emit ClaimsBurned(usr, balance);
        }
        ERC20(IFeed(feed).target()).balanceOf(address(this));
        ERC20(IFeed(feed).target()).safeTransfer(usr, collected);
        emit Collected(feed, maturity, collected);
    }

    /* ========== VIEW FUNCTIONS ========== */
    // TODO any?

    /* ========== ADMIN FUNCTIONS ========== */

    // @notice Enable or disable an feed
    // @dev Store the feed address in a registry for easy access on-chain
    // @param feed Feedr's address
    // @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) external override {
        require(feeds[feed] != isOn, Errors.ExistingValue);
        require(wards[msg.sender] == 1 || msg.sender == address(feed), Errors.NotAuthorised);
        feeds[feed] = isOn;
        emit FeedChanged(feed, isOn);
    }

    // @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    // @dev Reverts if the Series has already been settled or if the maturity is invalid
    // @dev Reverts if the Scale value is larger than the Scale from issuance, or if its above a certain threshold
    // @param feed Feed's address
    // @param maturity Maturity date for the Series
    // @param scale Value to set as the Series' Scale value at maturity
    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 scale,
        uint256[] memory values, // TODO: array of struct??
        address[] memory accounts
    ) external override onlyGov {
        require(_exists(feed, maturity), Errors.NotExists);
        require(scale > series[feed][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity.add(SPONSOR_WINDOW).add(SETTLEMENT_WINDOW);
        // If feed is disabled, it will allow the admin to backfill no matter the maturity.
        require(!feeds[feed] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);
        series[feed][maturity].mscale = scale;
        for (uint i = 0; i < accounts.length; i++) {
            lscales[feed][maturity][accounts[i]] = values[i];
        }
        _transferRewards(feed, maturity);
        emit Backfilled(feed, maturity, scale, values, accounts);
    }

    function _transferRewards(
        address feed,
        uint256 maturity
    ) internal {
        address to = block.timestamp <= maturity.add(SPONSOR_WINDOW) ? series[feed][maturity].sponsor : multisig;
        ERC20 target = ERC20(IFeed(feed).target());
        target.safeTransfer(multisig, series[feed][maturity].reward);
        ERC20(stable).safeTransfer(to, INIT_STAKE);
    }

    /* ========== AUTH FUNCTIONS ========== */

    function rely(address usr) external onlyGov {wards[usr] = 1;}

    function deny(address usr) external onlyGov {wards[usr] = 0;}


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
        ERC20 target = ERC20(IFeed(feed).target());
        (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(maturity);
        bytes32 date = bytes32(abi.encodePacked(year, "-", month, "-", day));

        string memory zname = string(abi.encodePacked(ZERO_NAME_PREFIX, " ", target.name(), " ", date));
        string memory zsymbol = string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", date));
        zero = address(new Zero(maturity, address(this), feed, zname, zsymbol));

        string memory cname = string(abi.encodePacked(CLAIM_NAME_PREFIX, " ", target.name(), " ", date));
        string memory csymbol = string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", date));
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

    modifier onlyGov() {
        require(wards[msg.sender] == 1, Errors.NotAuthorised);
        _;
    }

    modifier onlyClaim(address feed, uint256 maturity) {
        address callingContract = address(series[feed][maturity].claim);
        require(callingContract == msg.sender, "Can only be invoked by the Claim contract");
        _;
    }

    /* ========== EVENTS ========== */
    event SeriesInitialised(address zero, address claim, address sponsor);
    event SeriesSettled(address feed, uint256 maturity, address settler);
    event Issued(address feed, uint256 maturity, uint256 balance, address sender);
    event ZerosBurned(address account, uint256 zeros);
    event ClaimsBurned(address account, uint256 claims);
    event Combined(address feed, uint256 maturity, uint256 balance, address sender);
    event Backfilled(address feed, uint256 maturity, uint256 scale, uint256[] values, address[] accounts);
    event FeedChanged(address feed, bool isOn);
    event Collected(address feed, uint256 maturity, uint256 collected);
    event Redeemed(address feed, uint256 maturity, uint256 redeemed);
}
