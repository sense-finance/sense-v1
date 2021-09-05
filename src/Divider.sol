pragma solidity ^0.8.6;

// Internal references
import "./interfaces/IDivider.sol";
import "./interfaces/IFeed.sol";
import "./tokens/Zero.sol";
import "./tokens/Claim.sol";

// External references
import "./external/openzeppelin/SafeMath.sol";
import "./external/DateTime.sol";

// @title Divide tokens in two
// @notice You can use this contract to issue and redeem Sense ERC20 Zeros and Claims
// @dev The implementation of the following function will likely require utility functions and/or libraries,
// the usage thereof is left to the implementer
contract Divider is IDivider {
    using SafeMath for uint256;
    using SafeMath for uint256;

    address public stableAsset; // TODO: changeable?
    uint256 public constant ISSUANCE_FEE = 1e18 / 100; // In percentage (1%). Hardcoded value at least for v1.
    uint256 public constant SERIES_STAKE_AMOUNT = 1e18; // Hardcoded value at least for v1.
    uint public constant SPONSOR_WINDOW = 4 hours; // Hardcoded value at least for v1.
    uint public constant SETTLEMENT_WINDOW = 2 hours; // Hardcoded value at least for v1.

    bool private _paused = false;

    bytes32 private constant ZERO_SYMBOL_PREFIX = "z";
    bytes32 private constant ZERO_NAME_PREFIX = "Zero";
    bytes32 private constant CLAIM_SYMBOL_PREFIX = "c";
    bytes32 private constant CLAIM_NAME_PREFIX = "Claim";

    mapping(address => uint256) public wards;
    mapping(address => bool) public feeds;
    mapping(address => uint256) public activeSeries; // feed -> number of active series
    mapping(address => mapping(uint256 => Series)) public series; // feed -> maturity -> series
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lScaleValues; // feed -> maturity -> account -> lScale // TODO: check gas efficiency
    //    mapping(address => mapping(address => uint256)) public touches; // claim token address -> account -> last collect timestamp

    struct Series {
        address zero; // Zero address for this Series (deployed on Series initialization)
        address claim; // Claim address for this Series (deployed on Series initialization)
        address sponsor; // Series initializer/sponsor
        uint256 settlementReward; // Tracks the fees due to the settler on Settlement
        uint256 issuance; // Issuance date for this Series (needed for Zero redemption)
        // ^ Can be set to the date the timestamp the Series is initialized on
        uint256 iScale; // Scale value at issuance
        uint256 mScale; // Scale value at maturity
        uint256 stakedBalance; // Balance staked at initialisation (TBD)
        address stakeAsset; // Address of the stablecoin stake token (TBD)
        bool isSettled; // Whether the series has been settled or not (TBD)
    }

    constructor(address govAddress, address _stableAsset) {
        wards[govAddress] = 1;
        stableAsset = _stableAsset;
    }

    // -- views --
    function paused() public view returns (bool) {// TODO: add override?
        return _paused;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // @notice Initializes a new Series
    // @dev Reverts if the feed hasn't been approved or if the Maturity date is invalid
    // @dev Deploys two ERC20 contracts, one for each Zero type
    // @dev Transfers some fixed amount of stable asset to this contract
    // @param feed Feed to associate with the Series
    // @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(address feed, uint256 maturity) external override whenNotPaused returns (address zero, address claim) { // TODO: do we want to return the addresses?
        require(IERC20(stableAsset).allowance(msg.sender, address(this)) >= SERIES_STAKE_AMOUNT, "Allowance not high enough");
        require(feeds[feed], "Invalid feed address or feed is not enabled");
        require(activeSeries[feed] < 3, "Each Target type must have at most 3 active Series at once");

        (uint256 parsedMaturity, bytes32 stringifiedMaturity) = _checkAndParseMaturity(feed, maturity);
        require(!_seriesExists(feed, maturity), "Series with given maturity already exists");

        require(series[feed][parsedMaturity].issuance == 0, "A Series with the given maturity already exists");

        // transfer stable asset balance from msg.sender to this contract
        IERC20(stableAsset).transferFrom(msg.sender, address(this), SERIES_STAKE_AMOUNT);

        // TODO: on maturity date
        // 1. Fall on the first day of a month at exactly 0:00 UTC
        // 2. Be for at least a 2 weeks after initialization
        // 3. Not be the same as any other maturity date for the same feed address

        // Deploy Zero & Claim tokens
        address target = IFeed(feed).target();
        string memory name = IFeed(feed).name();
        string memory symbol = IFeed(feed).symbol();
        zero = _deployZero(
            string(abi.encodePacked(ZERO_NAME_PREFIX, " ", name, " ", stringifiedMaturity)),
            string(abi.encodePacked(ZERO_SYMBOL_PREFIX, symbol, ":", stringifiedMaturity)),
            maturity,
            feed
        );

        claim = _deployClaim(
            string(abi.encodePacked(ZERO_NAME_PREFIX, " ", name, " ", stringifiedMaturity)),
            string(abi.encodePacked(ZERO_SYMBOL_PREFIX, symbol, ":", stringifiedMaturity)),
            maturity,
            feed
        );

        Series memory newSeries = Series({
            zero : zero,
            claim : claim,
            sponsor : msg.sender,
            issuance : block.timestamp,
            settlementReward : 0,
            iScale : IFeed(feed).scale(),
            mScale : 0,
            isSettled : false, // TODO: maybe remove this variable?
            stakedBalance : SERIES_STAKE_AMOUNT,
            stakeAsset : stableAsset
        });
        series[feed][parsedMaturity] = newSeries;
        activeSeries[feed] = activeSeries[feed].add(1);
        require(zero != address(0));
        emit SeriesInitialised(zero, claim, msg.sender);
    }

    // @notice Settles a Series and transfer a settlement reward to the caller
    // @dev The Series' sponsor has a buffer where only they can settle the Series
    // @dev After the buffer, the reward becomes MEV
    // a Series that has matured but hasn't been officially settled yet
    // @param feed Feed to associate with the Series
    // @param maturity Maturity date for the new Series
    function settleSeries(address feed, uint256 maturity) external override whenNotPaused {
        require(_isSettable(feed, maturity), "Series is not settable");
        IERC20 target = IERC20(IFeed(feed).target());
        target.transfer(msg.sender, series[feed][maturity].settlementReward);
        IERC20(stableAsset).transfer(msg.sender, series[feed][maturity].stakedBalance); // TODO: are we gonna remove this if not Sponsor?
        series[feed][maturity].isSettled = true;
        if (series[feed][maturity].mScale == 0) { // if not 0, it means it was already stored on collect call.
            series[feed][maturity].mScale = IFeed(feed).scale();
            // save scale at maturity
        }
        activeSeries[feed] = activeSeries[feed].sub(1);
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
    ) external override whenNotPaused {
        require(feeds[feed], "Invalid feed address or feed is not enabled");
        require(_seriesExists(feed, maturity), "Series does not exist");
        IERC20 target = IERC20(IFeed(feed).target());
        require(target.allowance(msg.sender, address(this)) >= balance, "Allowance not high enough");
        target.transferFrom(msg.sender, address(this), balance);
        uint256 fee = balance.mul(ISSUANCE_FEE);
        // TODO: check precision (use rmul?)
        series[feed][maturity].settlementReward = series[feed][maturity].settlementReward.add(fee);

        // mint Zero and Claim tokens
        uint256 newBalance = balance.sub(fee);
        Zero(series[feed][maturity].zero).mint(msg.sender, newBalance);
        Claim(series[feed][maturity].claim).mint(msg.sender, newBalance);

        emit Issue(feed, maturity, balance, msg.sender);
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
    ) external override whenNotPaused {
        require(_seriesExists(feed, maturity), "Series does not exist");
        Zero zero = Zero(series[feed][maturity].zero);
        Claim claim = Claim(series[feed][maturity].claim);
        require(zero.balanceOf(msg.sender) >= balance);
        require(claim.balanceOf(msg.sender) >= balance);
        zero.burn(msg.sender, balance);
        claim.burn(msg.sender, balance);
        IERC20(IFeed(feed).target()).transfer(msg.sender, balance);
        emit Combined(feed, maturity, balance, msg.sender);
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
    ) external override whenNotPaused {
        // TODO: what would it be an invalid maturity?
        require(_seriesExists(feed, maturity), "Series does not exist");
        require(_isSettled(feed, maturity), "Series is not settled");
        require(balance > 0, "Nothing to redeem");

        // TODO: REVERT WHEN maturity + CUTOFF has been reached AND NO MATURITY VALUE

        // TODO: check precision
        Zero zero = Zero(series[feed][maturity].zero);
        require(zero.balanceOf(msg.sender) >= balance, "Not enough zeros to redeem");
        uint256 scaleAtIssuance = series[feed][maturity].iScale;
        uint256 scaleAtMaturity = series[feed][maturity].mScale;
        uint256 targetToTransfer = balance.div(scaleAtMaturity.div(scaleAtIssuance));
        zero.burn(msg.sender, balance);
        IERC20(IFeed(feed).target()).transfer(msg.sender, targetToTransfer);
        emit ZerosBurned(msg.sender, balance);
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
    ) external override onlyClaim(feed, maturity) returns (uint256 _collected) {
        // TODO: what would it be an invalid maturity?
        require(_seriesExists(feed, maturity), "Series does not exist");
        uint256 scale = series[feed][maturity].mScale;
        uint256 lScale = lScaleValues[feed][maturity][usr];
        Claim claim = Claim(series[feed][maturity].claim);
        //        uint256 touch = block.timestamp.sub(touches[address(claim)][usr]);
        if (lScale == 0) {
            lScale = series[feed][maturity].iScale;
        }
        if (block.timestamp >= maturity) {

            if (series[feed][maturity].mScale == 0) {
                scale = IFeed(feed).scale();
                series[feed][maturity].mScale = scale;
            }
            // TODO: REVERT WHEN maturity + CUTOFF has been reached AND NO MATURIRY VALUE
        } else {
            scale = IFeed(feed).scale();
        }
        // TODO: check precision
        require(claim.balanceOf(usr) >= balance, "Not enough claims to collect given target balance");
        uint256 targetToTransfer = balance.div(scale.div(scale.sub(lScale)));
        if (block.timestamp >= maturity) {
            claim.burn(usr, balance);
            emit ClaimsBurned(usr, balance);
        }
        lScaleValues[feed][maturity][usr] = IFeed(feed).scale();
        //        touches[address(claim)][usr] = block.timestamp;
        IERC20(IFeed(feed).target()).transfer(usr, targetToTransfer);
        return targetToTransfer;
    }

    /* ========== ADMIN FUNCTIONS ========== */

    // @notice Enable or disable an feed
    // @dev Store the feed address in a registry for easy access on-chain
    // @param feed Feedr's address
    // @param isOn Flag setting this feed to enabled or disabled
    function setFeed(address feed, bool isOn) external override onlyGov {
        require(feeds[feed] != isOn, "Boolean value is the current value");
        feeds[feed] = isOn;
        return;
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
        uint256 scale
    ) external override onlyGov {
        // TODO: what is an invalid maturity?
        require(!_isSettled(feed, maturity), "Series has already been settled");
        require(scale > series[feed][maturity].mScale, "Scale value can not be larger than scale at issuance");
        // TODO: threshold?
        series[feed][maturity].mScale = scale;
    }

    // @notice Stop the issuance of new Zeros or Claims
    // @dev Can set a simple storage bool
    // @dev Up to the implementer whether this should stop Series Initialization as well
    function stop() override onlyGov external {
        _paused = true;
        // TODO: settle active series?
    }

    // TODO: if we keep this setter, we should add logic for keeping track of which series have used which stake token
    function setStableAsset(address _stableAsset) override external onlyGov {
        stableAsset = _stableAsset;
    }

    /* ========== AUTH FUNCTIONS ========== */

    function rely(address usr) external onlyGov { wards[usr] = 1;}

    function deny(address usr) external onlyGov { wards[usr] = 0;}


    /* ========== INTERNAL & HELPER FUNCTIONS ========== */

    function _seriesExists(address feed, uint256 maturity) internal view returns (bool exists) {// TODO: convert into external (so anyone can check if a series exists) and internal
        return series[feed][maturity].zero != address(0);
    }

    function _isSettled(address feed, uint256 maturity) internal view returns (bool settled) {// TODO: convert into external (so anyone can check if a series exists) and internal
        return series[feed][maturity].isSettled;
    }

    function _isSettable(address feed, uint256 maturity) internal view returns (bool exists) {// TODO: convert into external (so anyone can check if a series exists) and internal
        require(_seriesExists(feed, maturity), "Series does not exist");
        require(!_isSettled(feed, maturity), "Series has already been settled");
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

    function _deployZero(
        string memory _name,
        string memory _symbol,
        uint256 _maturity,
        address _feed
    ) internal returns (address zero) {
        zero = address(new Zero(_maturity, address(this), _feed, _name, _symbol));
    }

    function _deployClaim(
        string memory _name,
        string memory _symbol,
        uint256 _maturity,
        address _feed
    ) internal returns (address zero) {
        zero = address(new Claim(_maturity, address(this), _feed, _name, _symbol));
    }

    function _checkAndParseMaturity(address feed, uint256 maturity) internal returns (uint256 parsedMaturity, bytes32 stringifiedMaturity) {// decouple into external and internal so anyone can use external to check validity of a maturity
        // check for duplicated Series
        require(series[feed][maturity].issuance == 0, "A Series with the given maturity already exists");
        require(maturity > block.timestamp + 2 weeks, "Invalid maturity");

        uint256 maturityDay = DateLib.getDay(maturity);
        require(maturityDay == 1, "Maturity day must be the 1st of the month");
        uint256 maturityMonth = DateLib.getMonth(maturity);
        uint256 maturityYear = DateLib.getYear(maturity);

        parsedMaturity = DateLib.timestampFromDate(maturityYear, maturityMonth, 1);
        stringifiedMaturity = bytes32(abi.encodePacked(maturityYear, "-", maturityMonth, "-", maturityDay));
    }

    /* ========== MODIFIERS ========== */

    function _onlyGov() internal view {
        require(wards[msg.sender] == 1, "Sender is not authorised");
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    function _onlyClaim(address feed, uint256 maturity) internal view {
        address callingContract = series[feed][maturity].claim;
        require(callingContract == msg.sender, "Can only be invoked by the Claim contract");
    }

    modifier onlyClaim(address feed, uint256 maturity) {
        _onlyClaim(feed, maturity);
        _;
    }

    function _whenNotPaused() internal view {
        require(!paused(), "Pausable: paused");
    }

    modifier whenNotPaused() {
        _whenNotPaused();
        _;
    }

    /* ========== EVENTS ========== */
    event SeriesInitialised(address zero, address claim, address sponsor);
    event SeriesSettled(address feed, uint256 maturity, address settler);
    event Issue(address feed, uint256 maturity, uint256 balance, address sender);
    event ZerosBurned(address account, uint256 zeros);
    event ClaimsBurned(address account, uint256 claims);
    event Combined(address feed, uint256 maturity, uint256 balance, address sender);
}
