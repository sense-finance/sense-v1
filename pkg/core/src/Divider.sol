// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { DateTime } from "./external/DateTime.sol";
import { FixedMath } from "./external/FixedMath.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Claim } from "./tokens/Claim.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";
import { Token as Zero } from "./tokens/Token.sol";

/// @title Sense Divider: Divide Assets in Two
/// @author fedealconada + jparklev
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Divider is Trust, ReentrancyGuard, Pausable {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;
    using Errors for string;

    /// @notice Configuration
    uint256 public constant SPONSOR_WINDOW = 4 hours; // TODO: TBD
    uint256 public constant SETTLEMENT_WINDOW = 2 hours; // TODO: TBD
    uint256 public constant ISSUANCE_FEE_CAP = 0.1e18; // 10% issuance fee cap

    /// @notice Program state
    address public periphery;
    address public immutable cup; // sense team multisig
    address public immutable tokenHandler; // zero/claim deployer
    bool public permissionless; // permissionless flag
    bool public guarded = true; // guarded launch flag
    uint256 public adapterCounter; // total # of adapters

    /// @notice adapter -> is supported
    mapping(address => bool) public adapters;
    /// @notice adapter ID -> adapter address
    mapping(uint256 => address) public adapterAddresses;
    /// @notice adapter address -> adapter ID
    mapping(address => uint256) public adapterIDs;
    /// @notice target -> max amount of Target allowed to be issued
    mapping(address => uint256) public guards;
    /// @notice adapter -> maturity -> Series
    mapping(address => mapping(uint256 => Series)) public series;
    /// @notice adapter -> maturity -> user -> lscale (last scale)
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lscales;

    struct Series {
        address zero; // Zero ERC20 token
        address claim; // Claim ERC20 token
        address sponsor; // actor who initialized the Series
        uint256 reward; // tracks fees due to the series' settler
        uint256 iscale; // scale at issuance
        uint256 mscale; // scale at maturity
        uint256 maxscale; // max scale value from this series' lifetime
        uint128 issuance; // timestamp of series initialization
        uint128 tilt; // % of underlying principal initially reserved for Claims
    }

    constructor(address _cup, address _tokenHandler) Trust(msg.sender) {
        cup = _cup;
        tokenHandler = _tokenHandler;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Enable an adapter
    /// @param adapter Adapter's address
    function addAdapter(address adapter) external whenPermissionless whenNotPaused {
        _setAdapter(adapter, true);
    }

    /// @notice Initializes a new Series
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Transfers some fixed amount of stake asset to this contract
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function initSeries(
        address adapter,
        uint48 maturity,
        address sponsor
    ) external onlyPeriphery whenNotPaused returns (address zero, address claim) {
        require(adapters[adapter], Errors.InvalidAdapter);
        require(!_exists(adapter, maturity), Errors.DuplicateSeries);
        require(_isValid(adapter, maturity), Errors.InvalidMaturity);

        // Transfer stake asset stake from caller to adapter
        (address target, , , , address stake, uint256 stakeSize, , , ) = Adapter(adapter).adapterParams();
        ERC20(stake).safeTransferFrom(msg.sender, adapter, _convertToBase(stakeSize, ERC20(stake).decimals()));

        // Deploy Zeros and Claims for this new Series
        (zero, claim) = TokenHandler(tokenHandler).deploy(adapter, maturity);

        // Initialize the new Series struct
        Series memory newSeries = Series({
            zero: zero,
            claim: claim,
            sponsor: sponsor,
            reward: 0,
            iscale: Adapter(adapter).scale(),
            mscale: 0,
            maxscale: Adapter(adapter).scale(),
            issuance: uint128(block.timestamp),
            tilt: Adapter(adapter).tilt()
        });

        series[adapter][maturity] = newSeries;

        emit SeriesInitialized(adapter, maturity, zero, claim, sponsor, target);
    }

    /// @notice Settles a Series and transfer the settlement reward to the caller
    /// @dev The Series' sponsor has a grace period where only they can settle the Series
    /// @dev After that, the reward becomes MEV
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the new Series
    function settleSeries(address adapter, uint48 maturity) external nonReentrant whenNotPaused {
        require(adapters[adapter], Errors.InvalidAdapter);
        require(_exists(adapter, maturity), Errors.SeriesDoesntExists);
        require(_canBeSettled(adapter, maturity), Errors.OutOfWindowBoundaries);

        // The maturity scale value is all a Series needs for us to consider it "settled"
        uint256 mscale = Adapter(adapter).scale();
        series[adapter][maturity].mscale = mscale;

        if (mscale > series[adapter][maturity].maxscale) {
            series[adapter][maturity].maxscale = mscale;
        }

        // Reward the caller for doing the work of settling the Series at around the correct time
        (address target, , , , address stake, uint256 stakeSize, , , ) = Adapter(adapter).adapterParams();
        ERC20(target).safeTransferFrom(adapter, msg.sender, series[adapter][maturity].reward);
        ERC20(stake).safeTransferFrom(adapter, msg.sender, _convertToBase(stakeSize, ERC20(stake).decimals()));

        emit SeriesSettled(adapter, maturity, msg.sender);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series [unix time]
    /// @param tBal Balance of Target to deposit
    /// @dev The balance of Zeros/Claims minted will be the same value in units of underlying (less fees)
    function issue(
        address adapter,
        uint48 maturity,
        uint256 tBal
    ) external nonReentrant whenNotPaused returns (uint256 uBal) {
        require(adapters[adapter], Errors.InvalidAdapter);
        require(_exists(adapter, maturity), Errors.SeriesDoesntExists);
        require(!_settled(adapter, maturity), Errors.IssueOnSettled);

        ERC20 target = ERC20(Adapter(adapter).getTarget());
        uint256 tDecimals = target.decimals();
        uint256 tBase = 10**tDecimals;
        uint256 fee;

        // Take the issuance fee out of the deposited Target, and put it towards the settlement reward
        uint256 issuanceFee = Adapter(adapter).getIssuanceFee();
        require(issuanceFee <= ISSUANCE_FEE_CAP, Errors.IssuanceFeeCapExceeded);

        if (tDecimals != 18) {
            uint256 base = (tDecimals < 18 ? issuanceFee / (10**(18 - tDecimals)) : issuanceFee * 10**(tDecimals - 18));
            fee = base.fmul(tBal, tBase);
        } else {
            fee = issuanceFee.fmul(tBal, tBase);
        }

        series[adapter][maturity].reward += fee;
        uint256 tBalSubFee = tBal - fee;

        // Ensure the caller won't hit the issuance cap with this action
        if (guarded) require(target.balanceOf(address(this)) + tBal <= guards[address(target)], Errors.GuardCapReached);
        target.safeTransferFrom(msg.sender, adapter, tBalSubFee);
        target.safeTransferFrom(msg.sender, adapter, fee);

        // Update values on adapter
        Adapter(adapter).notify(msg.sender, tBalSubFee, true);

        // If the caller has collected on Claims before, use the scale value from that collection to determine how many Zeros/Claims to mint
        // so that the Claims they mint here will have the same amount of yield stored up as their existing holdings
        uint256 scale = lscales[adapter][maturity][msg.sender];

        // If the caller has not collected on Claims before, use the current scale value to determine how many Zeros/Claims to mint
        // so that the Claims they mint here are "clean," in that they have no yet-to-be-collected yield
        if (scale == 0) {
            scale = Adapter(adapter).scale();
            lscales[adapter][maturity][msg.sender] = scale;
        }

        // Determine the amount of Underlying equal to the Target being sent in (the principal)
        uBal = tBalSubFee.fmul(scale, Zero(series[adapter][maturity].zero).BASE_UNIT());

        // Mint equal amounts of Zeros and Claims
        Zero(series[adapter][maturity].zero).mint(msg.sender, uBal);
        Claim(series[adapter][maturity].claim).mint(msg.sender, uBal);

        emit Issued(adapter, maturity, uBal, msg.sender);
    }

    /// @notice Reconstitute Target by burning Zeros and Claims
    /// @dev Explicitly burns claims before maturity, and implicitly does it at/after maturity through `_collect()`
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Zeros and Claims to burn
    function combine(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) external nonReentrant whenNotPaused returns (uint256 tBal) {
        require(adapters[adapter], Errors.InvalidAdapter);
        require(_exists(adapter, maturity), Errors.SeriesDoesntExists);

        // Burn the Zeros
        Zero(series[adapter][maturity].zero).burn(msg.sender, uBal);
        // Collect whatever excess is due
        _collect(msg.sender, adapter, maturity, uBal, uBal, address(0));

        // We use lscale since the current scale was already stored there in `_collect()`
        uint256 cscale = series[adapter][maturity].mscale;
        if (!_settled(adapter, maturity)) {
            // If it's not settled, then Claims won't be burned automatically in `_collect()`
            Claim(series[adapter][maturity].claim).burn(msg.sender, uBal);
            cscale = lscales[adapter][maturity][msg.sender];
        }

        // Convert from units of Underlying to units of Target
        ERC20 target = ERC20(Adapter(adapter).getTarget());
        tBal = uBal.fdiv(cscale, 10**target.decimals());
        target.safeTransferFrom(adapter, msg.sender, tBal);
        Adapter(adapter).notify(msg.sender, tBal, false);

        emit Combined(adapter, maturity, tBal, msg.sender);
    }

    /// @notice Burn Zeros of a Series once its been settled
    /// @dev The balance of redeemable Target is a function of the change in Scale
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Amount of Zeros to burn, which should be equivelent to the amount of Underlying owed to the caller
    function redeemZero(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) external nonReentrant whenNotPaused returns (uint256 tBal) {
        require(adapters[adapter], Errors.InvalidAdapter);
        // If a Series is settled, we know that it must have existed as well, so that check is unnecessary
        require(_settled(adapter, maturity), Errors.NotSettled);
        // Burn the caller's Zeros
        Zero(series[adapter][maturity].zero).burn(msg.sender, uBal);

        ERC20 target = ERC20(Adapter(adapter).getTarget());
        uint256 tBase = 10**ERC20(Adapter(adapter).getTarget()).decimals();
        // Amount of Target Zeros would ideally have
        tBal = (uBal * (FixedMath.WAD - series[adapter][maturity].tilt)) / series[adapter][maturity].mscale;

        if (series[adapter][maturity].mscale < series[adapter][maturity].maxscale) {
            // Amount of Target we actually have set aside for them (after collections from Claim holders)
            uint256 tBalZeroActual = (uBal * (FixedMath.WAD - series[adapter][maturity].tilt)) /
                series[adapter][maturity].maxscale;

            // Set our Target transfer value to the actual principal we have reserved for Zeros
            tBal = tBalZeroActual;

            // How much principal we have set aside for Claim holders
            uint256 tBalClaimActual = tBalZeroActual.fmul(series[adapter][maturity].tilt, tBase);

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

        target.safeTransferFrom(adapter, msg.sender, tBal);
        emit ZeroRedeemed(adapter, maturity, tBal);
    }

    function collect(
        address usr,
        address adapter,
        uint48 maturity,
        uint256 uBalTransfer,
        address to
    ) external nonReentrant onlyClaim(adapter, maturity) whenNotPaused returns (uint256 collected) {
        uint256 uBal = Claim(msg.sender).balanceOf(usr);
        return _collect(usr, adapter, maturity, uBal, uBalTransfer > 0 ? uBalTransfer : uBal, to);
    }

    /// @notice Collect Claim excess before, at, or after maturity
    /// @dev If `to` is set, we copy the lscale value from usr to this address
    /// @param usr User who's collecting for their Claims
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal claim balance
    /// @param uBalTransfer original transfer value
    /// @param to address to set the lscale value from usr
    function _collect(
        address usr,
        address adapter,
        uint48 maturity,
        uint256 uBal,
        uint256 uBalTransfer,
        address to
    ) internal returns (uint256 collected) {
        require(adapters[adapter], Errors.InvalidAdapter);
        require(_exists(adapter, maturity), Errors.SeriesDoesntExists);

        Series memory _series = series[adapter][maturity];

        // Get the scale value from the last time this holder collected (default to maturity)
        uint256 lscale = lscales[adapter][maturity][usr];
        Claim claim = Claim(series[adapter][maturity].claim);

        // If this is the Claim holder's first time collecting and nobody sent these Claims to them,
        // set the "last scale" value to the scale at issuance for this series
        if (lscale == 0) lscale = _series.iscale;

        // If the Series has been settled, this should be their last collect, so redeem the users claims for them
        if (_settled(adapter, maturity)) {
            _redeemClaim(usr, adapter, maturity, uBal);
        } else {
            // If we're not settled and we're past maturity + the sponsor window,
            // anyone can settle this Series so revert until someone does
            if (block.timestamp > maturity + SPONSOR_WINDOW) {
                revert(Errors.CollectNotSettled);
                // Otherwise, this is a valid pre-settlement collect and we need to determine the scale value
            } else {
                uint256 cscale = Adapter(adapter).scale();
                // If this is larger than the largest scale we've seen for this Series, use it
                if (cscale > _series.maxscale) {
                    _series.maxscale = cscale;
                    lscales[adapter][maturity][usr] = cscale;
                    // If not, use the previously noted max scale value
                } else {
                    lscales[adapter][maturity][usr] = _series.maxscale;
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
        ERC20(Adapter(adapter).getTarget()).safeTransferFrom(adapter, usr, collected);
        Adapter(adapter).notify(usr, collected, false); // distribute reward tokens

        // If this collect is a part of a token transfer to another address, set the receiver's
        // last collection to this scale (as all yield is being stripped off before the Claims are sent)
        if (to != address(0)) {
            uint256 cBal = ERC20(claim).balanceOf(to);
            // If receiver holds claims, we set lscale to a computed "synthetic" lscales value that, for the updated claim balance, still assigns the correct amount of yield.
            lscales[adapter][maturity][to] = cBal > 0
                ? _reweightLScale(adapter, maturity, cBal, uBal, to, _series.maxscale)
                : _series.maxscale;
            uint256 tBalTransfer = uBalTransfer.fdiv(_series.maxscale, claim.BASE_UNIT());
            Adapter(adapter).notify(usr, tBalTransfer, false);
            Adapter(adapter).notify(to, tBalTransfer, true);
        }

        emit Collected(adapter, maturity, collected);
    }

    function _reweightLScale(
        address adapter,
        uint256 maturity,
        uint256 cBal,
        uint256 uBal,
        address receiver,
        uint256 maxscale
    ) internal view returns (uint256) {
        uint256 uDecimals = ERC20(Adapter(adapter).underlying()).decimals();
        uint256 uBase = 10**uDecimals;
        return
            (cBal + uBal).fdiv(
                (cBal.fdiv(lscales[adapter][maturity][receiver], uBase) + uBal.fdiv(maxscale, uBase)),
                uBase
            );
    }

    function _redeemClaim(
        address usr,
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) internal {
        require(adapters[adapter], Errors.InvalidAdapter);
        // If a Series is settled, we know that it must have existed as well, so that check is unnecessary
        require(_settled(adapter, maturity), Errors.NotSettled);

        Series memory _series = series[adapter][maturity];

        // Burn the users's Claims
        Claim(_series.claim).burn(usr, uBal);

        ERC20 target = ERC20(Adapter(adapter).getTarget());

        uint256 tBal = 0;
        // If there's some principal set aside for Claims, determine whether they get it all
        if (_series.tilt != 0) {
            // Amount of Target we have set aside for Claims (Target * % set aside for Claims)
            tBal = (uBal * _series.tilt) / _series.maxscale;

            // If is down relative to its max, we'll try to take the shortfall out of Claim's principal
            if (_series.mscale < _series.maxscale) {
                // Amount of Target we would ideally have set aside for Zero holders
                uint256 tBalZeroIdeal = (uBal * (FixedMath.WAD - _series.tilt)) / _series.mscale;

                // Amount of Target we actually have set aside for them (after collections from Claim holders)
                uint256 tBalZeroActual = (uBal * (FixedMath.WAD - _series.tilt)) / _series.maxscale;

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
            target.safeTransferFrom(adapter, usr, tBal);
            Adapter(adapter).notify(usr, tBal, false);
        }

        emit ClaimRedeemed(adapter, maturity, tBal);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Enable or disable a adapter
    /// @param adapter Adapter's address
    /// @param isOn Flag setting this adapter to enabled or disabled
    function setAdapter(address adapter, bool isOn) public requiresTrust {
        _setAdapter(adapter, isOn);
    }

    /// @notice Set target's guard
    /// @param target Target address
    /// @param cap The max target that can be deposited on the Divider
    function setGuard(address target, uint256 cap) external requiresTrust {
        guards[target] = cap;
        emit GuardChanged(target, cap);
    }

    /// @notice Set guarded mode
    /// @param _guarded bool
    function setGuarded(bool _guarded) external requiresTrust {
        guarded = _guarded;
        emit GuardedChanged(guarded);
    }

    /// @notice Set periphery's contract
    /// @param _periphery Target address
    function setPeriphery(address _periphery) external requiresTrust {
        periphery = _periphery;
        emit PeripheryChanged(periphery);
    }

    /// @notice Set paused flag
    /// @param _paused boolean
    function setPaused(bool _paused) external requiresTrust {
        _paused ? _pause() : _unpause();
    }

    /// @notice Set permissioless mode
    /// @param _permissionless bool
    function setPermissionless(bool _permissionless) external requiresTrust {
        permissionless = _permissionless;
        emit PermissionlessChanged(permissionless);
    }

    /// @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    /// @param adapter Adapter's address
    /// @param maturity Maturity date for the Series
    /// @param mscale Value to set as the Series' Scale value at maturity
    /// @param _usrs Values to set on lscales mapping
    /// @param _lscales Values to set on lscales mapping
    function backfillScale(
        address adapter,
        uint48 maturity,
        uint256 mscale,
        address[] calldata _usrs,
        uint256[] calldata _lscales
    ) external requiresTrust {
        require(_exists(adapter, maturity), Errors.SeriesDoesntExists);
        require(mscale > series[adapter][maturity].iscale, Errors.InvalidScaleValue);

        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the adapter is disabled, it will allow the admin to backfill no matter the maturity
        require(!adapters[adapter] || block.timestamp > cutoff, Errors.OutOfWindowBoundaries);

        // Set the maturity scale for the Series (needed for `redeem` methods)
        series[adapter][maturity].mscale = mscale;
        if (mscale > series[adapter][maturity].maxscale) {
            series[adapter][maturity].maxscale = mscale;
        }
        // Set user's last scale values the Series (needed for the `collect` method)
        for (uint256 i = 0; i < _usrs.length; i++) {
            lscales[adapter][maturity][_usrs[i]] = _lscales[i];
        }

        (address target, , , , address stake, uint256 stakeSize, , , ) = Adapter(adapter).adapterParams();

        // Determine where the stake should go depending on where we are relative to the maturity date
        address stakeDst = block.timestamp <= maturity + SPONSOR_WINDOW ? series[adapter][maturity].sponsor : cup;
        uint256 reward = series[adapter][maturity].reward;

        ERC20(target).safeTransferFrom(adapter, cup, reward);
        ERC20(stake).safeTransferFrom(adapter, stakeDst, _convertToBase(stakeSize, ERC20(stake).decimals()));

        emit Backfilled(adapter, maturity, mscale, _usrs, _lscales);
    }

    /* ========== INTERNAL VIEWS ========== */

    function _exists(address adapter, uint48 maturity) internal view returns (bool) {
        return series[adapter][maturity].zero != address(0);
    }

    function _settled(address adapter, uint48 maturity) internal view returns (bool) {
        return series[adapter][maturity].mscale > 0;
    }

    function _canBeSettled(address adapter, uint48 maturity) internal view returns (bool) {
        require(!_settled(adapter, maturity), Errors.AlreadySettled);
        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the sender is the sponsor for the Series
        if (msg.sender == series[adapter][maturity].sponsor) {
            return maturity - SPONSOR_WINDOW <= block.timestamp && cutoff >= block.timestamp;
        } else {
            return maturity + SPONSOR_WINDOW < block.timestamp && cutoff >= block.timestamp;
        }
    }

    function _isValid(address adapter, uint48 maturity) internal view returns (bool) {
        (uint256 minm, uint256 maxm) = Adapter(adapter).getMaturityBounds();
        if (maturity < block.timestamp + minm || maturity > block.timestamp + maxm) return false;
        (, , uint256 day, uint256 hour, uint256 minute, uint256 second) = DateTime.timestampToDateTime(maturity);

        if (hour != 0 || minute != 0 || second != 0) return false;
        uint8 mode = Adapter(adapter).getMode();
        if (mode == 0) {
            return day == 1;
        }
        if (mode == 1) {
            return DateTime.getDayOfWeek(maturity) == 1;
        }
        return false;
    }

    /* ========== INTERNAL FNCTIONS & HELPERS ========== */

    function _setAdapter(address adapter, bool isOn) internal {
        require(adapters[adapter] != isOn, Errors.ExistingValue);
        adapters[adapter] = isOn;
        if (isOn) {
            adapterAddresses[adapterCounter] = adapter;
            adapterIDs[adapter] = adapterCounter;
            adapterCounter++;
        }

        emit AdapterChanged(adapter, adapterCounter, isOn);
    }

    function _convertToBase(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals != 18) {
            amount = decimals > 18 ? amount * 10**(decimals - 18) : amount / 10**(18 - decimals);
        }
        return amount;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyClaim(address adapter, uint48 maturity) {
        require(series[adapter][maturity].claim == msg.sender, "Can only be invoked by the Claim contract");
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
        address indexed adapter,
        uint256 indexed maturity,
        uint256 mscale,
        address[] _usrs,
        uint256[] _lscales
    );
    event GuardChanged(address indexed target, uint256 indexed cap);
    event AdapterChanged(address indexed adapter, uint256 indexed id, bool isOn);
    event PeripheryChanged(address indexed periphery);

    /// @notice Series lifecycle
    /// *---- beginning
    event SeriesInitialized(
        address adapter,
        uint256 indexed maturity,
        address zero,
        address claim,
        address indexed sponsor,
        address indexed target
    );
    /// -***- middle
    event Issued(address indexed adapter, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Combined(address indexed adapter, uint256 indexed maturity, uint256 balance, address indexed sender);
    event Collected(address indexed adapter, uint256 indexed maturity, uint256 collected);
    /// ----* end
    event SeriesSettled(address indexed adapter, uint256 indexed maturity, address indexed settler);
    event ZeroRedeemed(address indexed adapter, uint256 indexed maturity, uint256 redeemed);
    event ClaimRedeemed(address indexed adapter, uint256 indexed maturity, uint256 redeemed);
    /// *----* misc
    event GuardedChanged(bool indexed guarded);
    event PermissionlessChanged(bool indexed permissionless);
}

contract TokenHandler is Trust {
    /// @notice Configuration
    string private constant ZERO_SYMBOL_PREFIX = "z";
    string private constant ZERO_NAME_PREFIX = "Zero";
    string private constant CLAIM_SYMBOL_PREFIX = "c";
    string private constant CLAIM_NAME_PREFIX = "Claim";

    /// @notice Program state
    bool public inited;
    address public divider;

    constructor() Trust(msg.sender) {}

    function init(address _divider) external requiresTrust {
        require(!inited, "Already initialized");
        divider = _divider;
        inited = true;
    }

    function deploy(address adapter, uint48 maturity) external returns (address zero, address claim) {
        require(inited, "Not yet initialized");
        require(msg.sender == divider, "Must be called by the Divider");

        ERC20 target = ERC20(Adapter(adapter).getTarget());
        uint8 decimals = target.decimals();
        string memory name = target.name();
        (, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory datestring = string(abi.encodePacked(m, "-", y));

        string memory adapterId = DateTime.uintToString(Divider(divider).adapterIDs(adapter));
        zero = address(
            new Zero(
                string(abi.encodePacked(name, " ", datestring, " ", ZERO_NAME_PREFIX, " #", adapterId, " by Sense")),
                string(abi.encodePacked(ZERO_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId)),
                decimals,
                divider
            )
        );

        claim = address(
            new Claim(
                maturity,
                divider,
                adapter,
                string(abi.encodePacked(name, " ", datestring, " ", CLAIM_NAME_PREFIX, " #", adapterId, " by Sense")),
                string(abi.encodePacked(CLAIM_SYMBOL_PREFIX, target.symbol(), ":", datestring, ":#", adapterId)),
                decimals
            )
        );
    }
}
