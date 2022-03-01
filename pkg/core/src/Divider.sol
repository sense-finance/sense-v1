// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { DateTime } from "./external/DateTime.sol";
import { FixedMath } from "./external/FixedMath.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { Levels } from "@sense-finance/v1-utils/src/libs/Levels.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Claim } from "./tokens/Claim.sol";
import { Token } from "./tokens/Token.sol";
import { BaseAdapter as Adapter } from "./adapters/BaseAdapter.sol";

/// @title Sense Divider: Divide Assets in Two
/// @author fedealconada + jparklev
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Divider is Trust, ReentrancyGuard, Pausable {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;
    using Levels for uint256;

    /* ========== PUBLIC CONSTANTS ========== */

    /// @notice TODO(launch)
    uint256 public constant SPONSOR_WINDOW = 4 hours;

    /// @notice TODO(launch)
    uint256 public constant SETTLEMENT_WINDOW = 2 hours;

    /// @notice 10% issuance fee cap
    uint256 public constant ISSUANCE_FEE_CAP = 0.1e18; // TODO(launch)

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    address public periphery;

    /// @notice Sense team multisig
    address public immutable cup;

    /// @notice Zero/Claim deployer
    address public immutable tokenHandler;

    /// @notice Permissionless flag
    bool public permissionless;

    /// @notice Guarded launch flag
    bool public guarded = true;

    /// @notice Number of adapters (including turned off)
    uint248 public adapterCounter;

    /// @notice adapter ID -> adapter address
    mapping(uint256 => address) public adapterAddresses;

    /// @notice adapter data
    mapping(address => AdapterMeta) public adapterMeta;

    /// @notice adapter -> maturity -> Series
    mapping(address => mapping(uint256 => Series)) public series;

    /// @notice adapter -> maturity -> user -> lscale (last scale)
    mapping(address => mapping(uint256 => mapping(address => uint256))) public lscales;

    /* ========== DATA STRUCTURES ========== */

    struct Series {
        // Zero ERC20 token
        address zero;
        // Timestamp of series initialization
        uint48 issuance;
        // Claim ERC20 token
        address claim;
        // % of underlying principal initially reserved for Claims
        uint96 tilt;
        // Actor who initialized the Series
        address sponsor;
        // Tracks fees due to the series' settler
        uint256 reward;
        // Scale at issuance
        uint256 iscale;
        // Scale at maturity
        uint256 mscale;
        // Max scale value from this series' lifetime
        uint256 maxscale;
    }

    struct AdapterMeta {
        // Adapter ID
        uint248 id;
        // Adapter enabled/disabled
        bool enabled;
        // Max amount of Target allowed to be issued
        uint256 guard;
        // Underlying decimals
        uint8 uDecimals;
        // Adapter level
        uint248 level;
    }

    constructor(address _cup, address _tokenHandler) Trust(msg.sender) {
        cup = _cup;
        tokenHandler = _tokenHandler;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Enable an adapter (only when permissionless mode on or if called from periphery)
    /// @param adapter Adapter's address
    function addAdapter(address adapter) external whenNotPaused {
        if (!permissionless && msg.sender != periphery) revert Errors.OnlyPermissionless();
        if (adapterMeta[adapter].id > 0 && !adapterMeta[adapter].enabled) revert Errors.InvalidAdapter();
        _setAdapter(adapter, true);
    }

    /// @notice Initializes a new Series
    /// @dev Deploys two ERC20 contracts, one for each Zero type
    /// @dev Transfers some fixed amount of stake asset to this contract
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    /// @param sponsor Sponsor of the Series that puts up a token stake and receives the issuance fees
    function initSeries(
        address adapter,
        uint256 maturity,
        address sponsor
    ) external nonReentrant whenNotPaused returns (address zero, address claim) {
        if (periphery != msg.sender) revert Errors.OnlyPeriphery();
        if (!adapterMeta[adapter].enabled) revert Errors.InvalidAdapter();
        if (_exists(adapter, maturity)) revert Errors.DuplicateSeries();
        if (!_isValid(adapter, maturity)) revert Errors.InvalidMaturity();

        // Transfer stake asset stake from caller to adapter
        (address target, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();

        // Deploy Zeros and Claims for this new Series
        (zero, claim) = TokenHandler(tokenHandler).deploy(adapter, adapterMeta[adapter].id, maturity);

        // Initialize the new Series struct
        uint256 scale = Adapter(adapter).scale();

        series[adapter][maturity].zero = zero;
        series[adapter][maturity].issuance = uint48(block.timestamp);
        series[adapter][maturity].claim = claim;
        series[adapter][maturity].tilt = uint96(Adapter(adapter).tilt());
        series[adapter][maturity].sponsor = sponsor;
        series[adapter][maturity].iscale = scale;
        series[adapter][maturity].maxscale = scale;

        ERC20(stake).safeTransferFrom(msg.sender, adapter, stakeSize);

        emit SeriesInitialized(adapter, maturity, zero, claim, sponsor, target);
    }

    /// @notice Settles a Series and transfers the settlement reward to the caller
    /// @dev The Series' sponsor has a grace period where only they can settle the Series
    /// @dev After that, the reward becomes MEV
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the new Series
    function settleSeries(address adapter, uint256 maturity) external nonReentrant whenNotPaused {
        if (!adapterMeta[adapter].enabled) revert Errors.InvalidAdapter();
        if (!_exists(adapter, maturity)) revert Errors.SeriesDoesNotExist();
        if (_settled(adapter, maturity)) revert Errors.AlreadySettled();
        if (!_canBeSettled(adapter, maturity)) revert Errors.OutOfWindowBoundaries();

        // The maturity scale value is all a Series needs for us to consider it "settled"
        uint256 mscale = Adapter(adapter).scale();
        series[adapter][maturity].mscale = mscale;

        if (mscale > series[adapter][maturity].maxscale) {
            series[adapter][maturity].maxscale = mscale;
        }

        // Reward the caller for doing the work of settling the Series at around the correct time
        (address target, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();
        ERC20(target).safeTransferFrom(adapter, msg.sender, series[adapter][maturity].reward);
        ERC20(stake).safeTransferFrom(adapter, msg.sender, stakeSize);

        emit SeriesSettled(adapter, maturity, msg.sender);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series [unix time]
    /// @param tBal Balance of Target to deposit
    /// @dev The balance of Zeros/Claims minted will be the same value in units of underlying (less fees)
    function issue(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) external nonReentrant whenNotPaused returns (uint256 uBal) {
        if (!adapterMeta[adapter].enabled) revert Errors.InvalidAdapter();
        if (!_exists(adapter, maturity)) revert Errors.SeriesDoesNotExist();
        if (_settled(adapter, maturity)) revert Errors.IssueOnSettle();

        uint256 level = adapterMeta[adapter].level;
        if (level.issueRestricted() && msg.sender != adapter) revert Errors.IssuanceRestricted();

        ERC20 target = ERC20(Adapter(adapter).target());

        // Take the issuance fee out of the deposited Target, and put it towards the settlement reward
        uint256 issuanceFee = Adapter(adapter).ifee();
        if (issuanceFee > ISSUANCE_FEE_CAP) revert Errors.IssuanceFeeCapExceeded();
        uint256 fee = tBal.fmul(issuanceFee);

        unchecked {
            // Safety: bounded by the Target's total token supply
            series[adapter][maturity].reward += fee;
        }
        uint256 tBalSubFee = tBal - fee;

        // Ensure the caller won't hit the issuance cap with this action
        unchecked {
            // Safety: bounded by the Target's total token supply
            if (guarded && target.balanceOf(adapter) + tBal > adapterMeta[address(adapter)].guard)
                revert Errors.GuardCapReached();
        }

        // Update values on adapter
        Adapter(adapter).notify(msg.sender, tBalSubFee, true);

        uint256 scale = level.collectDisabled() ? series[adapter][maturity].iscale : Adapter(adapter).scale();

        // Determine the amount of Underlying equal to the Target being sent in (the principal)
        uBal = tBalSubFee.fmul(scale);

        // If the caller has not collected on Claims before, use the current scale, otherwise
        // use the harmonic mean of the last and the current scale value
        lscales[adapter][maturity][msg.sender] = lscales[adapter][maturity][msg.sender] == 0
            ? scale
            : _reweightLScale(
                adapter,
                maturity,
                Claim(series[adapter][maturity].claim).balanceOf(msg.sender),
                uBal,
                msg.sender,
                scale
            );

        // Mint equal amounts of Zeros and Claims
        Token(series[adapter][maturity].zero).mint(msg.sender, uBal);
        Claim(series[adapter][maturity].claim).mint(msg.sender, uBal);

        target.safeTransferFrom(msg.sender, adapter, tBal);

        emit Issued(adapter, maturity, uBal, msg.sender);
    }

    /// @notice Reconstitute Target by burning Zeros and Claims
    /// @dev Explicitly burns claims before maturity, and implicitly does it at/after maturity through `_collect()`
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Zeros and Claims to burn
    function combine(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) external nonReentrant whenNotPaused returns (uint256 tBal) {
        if (!adapterMeta[adapter].enabled) revert Errors.InvalidAdapter();
        if (!_exists(adapter, maturity)) revert Errors.SeriesDoesNotExist();

        uint256 level = adapterMeta[adapter].level;
        if (level.combineRestricted() && msg.sender != adapter) revert Errors.CombineRestricted();

        // Burn the Zeros
        Token(series[adapter][maturity].zero).burn(msg.sender, uBal);

        // Collect whatever excess is due
        uint256 collected = _collect(msg.sender, adapter, maturity, uBal, uBal, address(0));

        uint256 cscale = series[adapter][maturity].mscale;
        bool settled = _settled(adapter, maturity);
        if (!settled) {
            // If it's not settled, then Claims won't be burned automatically in `_collect()`
            Claim(series[adapter][maturity].claim).burn(msg.sender, uBal);
            // If collect has been restricted, use the initial scale, otherwise use the current scale
            cscale = level.collectDisabled()
                ? series[adapter][maturity].iscale
                : lscales[adapter][maturity][msg.sender];
        }

        // Convert from units of Underlying to units of Target
        tBal = uBal.fdiv(cscale);
        ERC20(Adapter(adapter).target()).safeTransferFrom(adapter, msg.sender, tBal);

        // Notify only when Series is not settled as when it is, the _collect() call above would trigger a redeemClaim which will call notify
        if (!settled) Adapter(adapter).notify(msg.sender, tBal, false);
        unchecked {
            // Safety: bounded by the Target's total token supply
            tBal += collected;
        }
        emit Combined(adapter, maturity, tBal, msg.sender);
    }

    /// @notice Burn Zeros of a Series once it's been settled
    /// @dev The balance of redeemable Target is a function of the change in Scale
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Amount of Zeros to burn, which should be equivalent to the amount of Underlying owed to the caller
    function redeemZero(
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) external nonReentrant whenNotPaused returns (uint256 tBal) {
        // If a Series is settled, we know that it must have existed as well, so that check is unnecessary
        if (!_settled(adapter, maturity)) revert Errors.NotSettled();

        uint256 level = adapterMeta[adapter].level;
        if (level.redeemZeroRestricted() && msg.sender == adapter) revert Errors.RedeemZeroRestricted();

        // Burn the caller's Zeros
        Token(series[adapter][maturity].zero).burn(msg.sender, uBal);

        // Zero holder's share of the principal = (1 - part of the principal that belongs to Claims)
        uint256 zShare = FixedMath.WAD - series[adapter][maturity].tilt;

        // If Zeros are at a loss and Claims have some principal to help cover the shortfall,
        // take what we can from Claim's principal
        if (series[adapter][maturity].mscale.fdiv(series[adapter][maturity].maxscale) >= zShare) {
            tBal = (uBal * zShare) / series[adapter][maturity].mscale;
        } else {
            tBal = uBal.fdiv(series[adapter][maturity].maxscale);
        }

        if (!level.redeemZeroHookDisabled()) {
            Adapter(adapter).onZeroRedeem(
                uBal,
                series[adapter][maturity].mscale,
                series[adapter][maturity].maxscale,
                tBal
            );
        }

        ERC20(Adapter(adapter).target()).safeTransferFrom(adapter, msg.sender, tBal);
        emit ZeroRedeemed(adapter, maturity, tBal);
    }

    function collect(
        address usr,
        address adapter,
        uint256 maturity,
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
        uint256 maturity,
        uint256 uBal,
        uint256 uBalTransfer,
        address to
    ) internal returns (uint256 collected) {
        if (!_exists(adapter, maturity)) revert Errors.SeriesDoesNotExist();

        // If the adapter is disabled, its Claims can only collect
        // if associated Series has been settled, which implies that an admin
        // has backfilled it
        if (!adapterMeta[adapter].enabled && !_settled(adapter, maturity)) revert Errors.InvalidAdapter();

        Series memory _series = series[adapter][maturity];

        // Get the scale value from the last time this holder collected (default to maturity)
        uint256 lscale = lscales[adapter][maturity][usr];

        uint256 level = adapterMeta[adapter].level;
        if (level.collectDisabled()) {
            // If this Series has been settled, we ensure everyone's Claims will
            // collect yield accrued since issuance
            if (_settled(adapter, maturity)) {
                lscale = series[adapter][maturity].iscale;
                // If the Series is not settled, we ensure no collections can happen
            } else {
                return 0;
            }
        }

        // If the Series has been settled, this should be their last collect, so redeem the user's claims for them
        if (_settled(adapter, maturity)) {
            _redeemClaim(usr, adapter, maturity, uBal);
        } else {
            // If we're not settled and we're past maturity + the sponsor window,
            // anyone can settle this Series so revert until someone does
            if (block.timestamp > maturity + SPONSOR_WINDOW) {
                revert Errors.CollectNotSettled();
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
        uint256 tBalNow = uBal.fdivUp(_series.maxscale); // preventive round-up towards the protocol
        uint256 tBalPrev = uBal.fdiv(lscale);
        unchecked {
            collected = tBalPrev > tBalNow ? tBalPrev - tBalNow : 0;
        }
        ERC20(Adapter(adapter).target()).safeTransferFrom(adapter, usr, collected);
        Adapter(adapter).notify(usr, collected, false); // Distribute reward tokens

        // If this collect is a part of a token transfer to another address, set the receiver's
        // last collection to a synthetic scale weighted based on the scale on their last collect,
        // the time elapsed, and the current scale
        if (to != address(0)) {
            uint256 cBal = Claim(_series.claim).balanceOf(to);
            // If receiver holds claims, we set lscale to a computed "synthetic" lscales value that,
            // for the updated claim balance, still assigns the correct amount of yield.
            lscales[adapter][maturity][to] = cBal > 0
                ? _reweightLScale(adapter, maturity, cBal, uBalTransfer, to, _series.maxscale)
                : _series.maxscale;
            uint256 tBalTransfer = uBalTransfer.fdiv(_series.maxscale);
            Adapter(adapter).notify(usr, tBalTransfer, false);
            Adapter(adapter).notify(to, tBalTransfer, true);
        }
        series[adapter][maturity] = _series;

        emit Collected(adapter, maturity, collected);
    }

    /// @notice calculate the harmonic mean of the current scale and the last scale,
    /// weighted by amounts associated with each
    function _reweightLScale(
        address adapter,
        uint256 maturity,
        uint256 cBal,
        uint256 uBal,
        address receiver,
        uint256 scale
    ) internal view returns (uint256) {
        uint256 uBase = 10**adapterMeta[adapter].uDecimals;
        return (cBal + uBal).fdiv((cBal.fdiv(lscales[adapter][maturity][receiver]) + uBal.fdiv(scale)), uBase);
    }

    function _redeemClaim(
        address usr,
        address adapter,
        uint256 maturity,
        uint256 uBal
    ) internal {
        // Burn the users's Claims
        Claim(series[adapter][maturity].claim).burn(usr, uBal);

        // Default principal for Claim
        uint256 tBal = 0;

        // Zero holder's share of the principal = (1 - part of the principal that belongs to Claims)
        uint256 zShare = FixedMath.WAD - series[adapter][maturity].tilt;

        // If Zeros are at a loss and Claims had their principal cut to help cover the shortfall,
        // calculate how much Claims have left
        if (series[adapter][maturity].mscale.fdiv(series[adapter][maturity].maxscale) >= zShare) {
            tBal = uBal.fdiv(series[adapter][maturity].maxscale) - (uBal * zShare) / series[adapter][maturity].mscale;
            ERC20(Adapter(adapter).target()).safeTransferFrom(adapter, usr, tBal);
        }

        // Always notify the Adapter of the full Target balance that will no longer
        // have its rewards distributed
        Adapter(adapter).notify(usr, uBal.fdivUp(series[adapter][maturity].maxscale), false);

        emit ClaimRedeemed(adapter, maturity, tBal);
    }

    /* ========== ADMIN ========== */

    /// @notice Enable or disable a adapter
    /// @param adapter Adapter's address
    /// @param isOn Flag setting this adapter to enabled or disabled
    function setAdapter(address adapter, bool isOn) public requiresTrust {
        _setAdapter(adapter, isOn);
    }

    /// @notice Set adapter's guard
    /// @param adapter Adapter address
    /// @param cap The max target that can be deposited on the Adapter
    function setGuard(address adapter, uint256 cap) external requiresTrust {
        adapterMeta[adapter].guard = cap;
        emit GuardChanged(adapter, cap);
    }

    /// @notice Set guarded mode
    /// @param _guarded bool
    function setGuarded(bool _guarded) external requiresTrust {
        guarded = _guarded;
        emit GuardedChanged(_guarded);
    }

    /// @notice Set periphery's contract
    /// @param _periphery Target address
    function setPeriphery(address _periphery) external requiresTrust {
        periphery = _periphery;
        emit PeripheryChanged(_periphery);
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
        emit PermissionlessChanged(_permissionless);
    }

    /// @notice Backfill a Series' Scale value at maturity if keepers failed to settle it
    /// @param adapter Adapter's address
    /// @param maturity Maturity date for the Series
    /// @param mscale Value to set as the Series' Scale value at maturity
    /// @param _usrs Values to set on lscales mapping
    /// @param _lscales Values to set on lscales mapping
    function backfillScale(
        address adapter,
        uint256 maturity,
        uint256 mscale,
        address[] calldata _usrs,
        uint256[] calldata _lscales
    ) external requiresTrust {
        if (!_exists(adapter, maturity)) revert Errors.SeriesDoesNotExist();

        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the adapter is disabled, it will allow the admin to backfill no matter the maturity
        if (adapterMeta[adapter].enabled && block.timestamp <= cutoff) revert Errors.OutOfWindowBoundaries();

        // Set user's last scale values the Series (needed for the `collect` method)
        for (uint256 i = 0; i < _usrs.length; i++) {
            lscales[adapter][maturity][_usrs[i]] = _lscales[i];
        }

        if (mscale > 0) {
            Series memory _series = series[adapter][maturity];
            // Set the maturity scale for the Series (needed for `redeem` methods)
            series[adapter][maturity].mscale = mscale;
            if (mscale > _series.maxscale) {
                series[adapter][maturity].maxscale = mscale;
            }

            (address target, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();

            address stakeDst = adapterMeta[adapter].enabled ? cup : _series.sponsor;
            ERC20(target).safeTransferFrom(adapter, cup, _series.reward);
            series[adapter][maturity].reward = 0;
            ERC20(stake).safeTransferFrom(adapter, stakeDst, stakeSize);
        }

        emit Backfilled(adapter, maturity, mscale, _usrs, _lscales);
    }

    /* ========== INTERNAL VIEWS ========== */

    function _exists(address adapter, uint256 maturity) internal view returns (bool) {
        return series[adapter][maturity].zero != address(0);
    }

    function _settled(address adapter, uint256 maturity) internal view returns (bool) {
        return series[adapter][maturity].mscale > 0;
    }

    function _canBeSettled(address adapter, uint256 maturity) internal view returns (bool) {
        uint256 cutoff = maturity + SPONSOR_WINDOW + SETTLEMENT_WINDOW;
        // If the sender is the sponsor for the Series
        if (msg.sender == series[adapter][maturity].sponsor) {
            return maturity - SPONSOR_WINDOW <= block.timestamp && cutoff >= block.timestamp;
        } else {
            return maturity + SPONSOR_WINDOW < block.timestamp && cutoff >= block.timestamp;
        }
    }

    function _isValid(address adapter, uint256 maturity) internal view returns (bool) {
        (uint256 minm, uint256 maxm) = Adapter(adapter).getMaturityBounds();
        if (maturity < block.timestamp + minm || maturity > block.timestamp + maxm) return false;
        (, , uint256 day, uint256 hour, uint256 minute, uint256 second) = DateTime.timestampToDateTime(maturity);

        if (hour != 0 || minute != 0 || second != 0) return false;
        uint256 mode = Adapter(adapter).mode();
        if (mode == 0) {
            return day == 1;
        }
        if (mode == 1) {
            return DateTime.getDayOfWeek(maturity) == 1;
        }
        return false;
    }

    /* ========== INTERNAL UTILS ========== */

    function _setAdapter(address adapter, bool isOn) internal {
        AdapterMeta memory am = adapterMeta[adapter];
        if (am.enabled == isOn) revert Errors.ExistingValue();
        am.enabled = isOn;

        // If this adapter is being added for the first time
        if (isOn && am.id == 0) {
            am.id = ++adapterCounter;
            adapterAddresses[am.id] = adapter;
        }

        // Set level, target and underlying decimals (can only be done once);
        am.uDecimals = ERC20(Adapter(adapter).underlying()).decimals();
        am.level = uint248(Adapter(adapter).level());
        adapterMeta[adapter] = am;
        emit AdapterChanged(adapter, am.id, isOn);
    }

    /* ========== PUBLIC GETTERS ========== */

    /// @notice Returns address of zero token
    function zero(address adapter, uint256 maturity) public view returns (address) {
        return series[adapter][maturity].zero;
    }

    /// @notice Returns address of claim token
    function claim(address adapter, uint256 maturity) public view returns (address) {
        return series[adapter][maturity].claim;
    }

    function mscale(address adapter, uint256 maturity) public view returns (uint256) {
        return series[adapter][maturity].mscale;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyClaim(address adapter, uint256 maturity) {
        if (series[adapter][maturity].claim != msg.sender) revert Errors.OnlyClaim();
        _;
    }

    /* ========== LOGS ========== */

    /// @notice Admin
    event Backfilled(
        address indexed adapter,
        uint256 indexed maturity,
        uint256 mscale,
        address[] _usrs,
        uint256[] _lscales
    );
    event GuardChanged(address indexed adapter, uint256 cap);
    event AdapterChanged(address indexed adapter, uint256 indexed id, bool indexed isOn);
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
    /// @notice Program state
    address public divider;

    constructor() Trust(msg.sender) {}

    function init(address _divider) external requiresTrust {
        if (divider != address(0)) revert Errors.AlreadyInitialized();
        divider = _divider;
    }

    function deploy(
        address adapter,
        uint248 id,
        uint256 maturity
    ) external returns (address zero, address claim) {
        if (msg.sender != divider) revert Errors.OnlyDivider();

        ERC20 target = ERC20(Adapter(adapter).target());
        uint8 decimals = target.decimals();
        string memory symbol = target.symbol();
        (string memory d, string memory m, string memory y) = DateTime.toDateString(maturity);
        string memory date = DateTime.format(maturity);
        string memory datestring = string(abi.encodePacked(d, "-", m, "-", y));
        string memory adapterId = DateTime.uintToString(id);
        zero = address(
            new Token(
                string(abi.encodePacked(date, " ", target.symbol(), " Sense Principal Token, A", adapterId)),
                string(abi.encodePacked("sP-", target.symbol(), ":", datestring, ":", adapterId)),
                decimals,
                divider
            )
        );

        claim = address(
            new Claim(
                adapter,
                maturity,
                string(abi.encodePacked(date, " ", target.symbol(), " Sense Yield Token, A", adapterId)),
                string(abi.encodePacked("sY-", target.symbol(), ":", datestring, ":", adapterId)),
                decimals,
                divider
            )
        );
    }
}
