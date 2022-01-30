// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External reference
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";
import { PriceOracle } from "./external/PriceOracle.sol";
import { BalancerOracle } from "./external/BalancerOracle.sol";

// Internal references
import { UnderlyingOracle } from "./oracles/Underlying.sol";
import { TargetOracle } from "./oracles/Target.sol";
import { ZeroOracle } from "./oracles/Zero.sol";
import { LPOracle } from "./oracles/LP.sol";

import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Divider } from "@sense-finance/v1-core/src/Divider.sol";
import { BaseAdapter as Adapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

interface FuseDirectoryLike {
    function deployPool(
        string memory name,
        address implementation,
        bool enforceWhitelist,
        uint256 closeFactor,
        uint256 liquidationIncentive,
        address priceOracle
    ) external returns (uint256, address);
}

interface ComptrollerLike {
    function _deployMarket(
        bool isCEther,
        bytes calldata constructorData,
        uint256 collateralFactorMantissa
    ) external returns (uint256);

    function _acceptAdmin() external returns (uint256);

    function cTokensByUnderlying(address underlying) external view returns (address);

    function markets(address cToken) external view returns (bool, uint256);
}

interface MasterOracleLike {
    function initialize(
        address[] memory underlyings,
        PriceOracle[] memory _oracles,
        PriceOracle _defaultOracle,
        address _admin,
        bool _canAdminOverwrite
    ) external;

    function add(address[] calldata underlyings, PriceOracle[] calldata _oracles) external;
}

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Implementation of Fuse's comptroller
    address public immutable comptrollerImpl;

    /// @notice Implementation of Fuse's cERC20
    address public immutable cERC20Impl;

    /// @notice Fuse's pool directory
    address public immutable fuseDirectory;

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Implementation of Fuse's master oracle that routes to individual asset oracles
    address public immutable oracleImpl;

    /// @notice Sense oracle for SEnse Targets
    address public immutable targetOracle;

    /// @notice Sense oracle for Sense Zeros
    address public immutable zeroOracle;

    /// @notice Sense oracle for Space LP Shares
    address public immutable lpOracle;

    /// @notice Sense oracle for Underlying assets
    address public immutable underlyingOracle;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    /// @notice Fuse comptroller for the Sense pool
    address public comptroller;

    /// @notice Master oracle for Sense's assets deployed on Fuse
    address public masterOracle;

    /// @notice Fuse param config
    AssetParams public targetParams;
    AssetParams public zeroParams;
    AssetParams public lpTokenParams;

    /// @notice Series Pools: adapter -> maturity -> (series status (zeros/lp shares), AMM pool)
    mapping(address => mapping(uint256 => Series)) public sSeries;

    /* ========== ENUMS ========== */

    enum SeriesStatus {
        NONE,
        QUEUED,
        ADDED
    }

    /* ========== DATA STRUCTURES ========== */

    struct AssetParams {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }

    struct Series {
        // Series addition status
        SeriesStatus status;
        // Space pool for this Series
        address pool;
    }

    constructor(
        address _fuseDirectory,
        address _comptrollerImpl,
        address _cERC20Impl,
        address _divider,
        address _oracleImpl
    ) Trust(msg.sender) {
        fuseDirectory = _fuseDirectory;
        comptrollerImpl = _comptrollerImpl;
        cERC20Impl = _cERC20Impl;
        divider = _divider;
        oracleImpl = _oracleImpl;

        targetOracle = address(new TargetOracle());
        zeroOracle = address(new ZeroOracle());
        lpOracle = address(new LPOracle());
        underlyingOracle = address(new UnderlyingOracle());
    }

    function deployPool(
        string calldata name,
        uint256 closeFactor,
        uint256 liqIncentive,
        address fallbackOracle
    ) external requiresTrust returns (uint256 _poolIndex, address _comptroller) {
        masterOracle = Clones.cloneDeterministic(oracleImpl, Bytes32AddressLib.fillLast12Bytes(address(this)));
        MasterOracleLike(masterOracle).initialize(
            new address[](0),
            new PriceOracle[](0),
            PriceOracle(fallbackOracle), // default oracle used if asset prices can't be found otherwise
            address(this), // admin
            true // admin can override existing oracle routes
        );

        (_poolIndex, _comptroller) = FuseDirectoryLike(fuseDirectory).deployPool(
            name,
            comptrollerImpl,
            false, // `whitelist` is always false
            closeFactor,
            liqIncentive,
            masterOracle
        );

        uint256 err = ComptrollerLike(_comptroller)._acceptAdmin();
        if (err != 0) revert Errors.FailedBecomeAdmin();
        comptroller = _comptroller;

        emit PoolDeployed(name, _comptroller, _poolIndex, closeFactor, liqIncentive);
    }

    function addTarget(address target, address adapter) external requiresTrust returns (address cTarget) {
        if (comptroller == address(0)) revert Errors.PoolNotDeployed();
        if (targetParams.irModel == address(0)) revert Errors.TargetParamsNotSet();

        address underlying = Adapter(adapter).underlying();

        address[] memory underlyings = new address[](2);
        underlyings[0] = target;
        underlyings[1] = underlying;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        oracles[0] = PriceOracle(targetOracle);
        oracles[1] = PriceOracle(underlyingOracle);

        UnderlyingOracle(underlyingOracle).setUnderlying(underlying, adapter);
        TargetOracle(targetOracle).setTarget(target, adapter);
        MasterOracleLike(masterOracle).add(underlyings, oracles);

        bytes memory constructorData = abi.encode(
            target,
            comptroller,
            targetParams.irModel,
            ERC20(target).name(),
            ERC20(target).symbol(),
            cERC20Impl,
            hex"", // calldata sent to becomeImplementation (currently unused)
            targetParams.reserveFactor,
            0 // no admin fee
        );

        // Trying to deploy the same market twice will fail
        uint256 err = ComptrollerLike(comptroller)._deployMarket(false, constructorData, targetParams.collateralFactor);
        if (err != 0) revert Errors.FailedAddMarket();

        cTarget = ComptrollerLike(comptroller).cTokensByUnderlying(target);

        emit TargetAdded(target, cTarget);
    }

    /// @notice queues a set of (Zero, LPShare) for a  Fuse pool once the TWAP is ready
    /// @dev called by the Periphery, which will know which pool address to set for this Series
    function queueSeries(
        address adapter,
        uint256 maturity,
        address pool
    ) external requiresTrust {
        if (Divider(divider).zero(adapter, maturity) == address(0)) revert Errors.SeriesDoesNotExist();
        if (sSeries[adapter][maturity].status != SeriesStatus.NONE) revert Errors.DuplicateSeries();

        address cTarget = ComptrollerLike(comptroller).cTokensByUnderlying(Adapter(adapter).target());
        if (cTarget == address(0)) revert Errors.TargetNotInFuse();

        (bool isListed, ) = ComptrollerLike(comptroller).markets(cTarget);
        if (!isListed) revert Errors.TargetNotInFuse();

        sSeries[adapter][maturity] = Series({ status: SeriesStatus.QUEUED, pool: pool });

        emit SeriesQueued(adapter, maturity, pool);
    }

    /// @notice open method to add queued Zeros and LPShares to Fuse pool
    /// @dev this can only be done once the yield space pool has filled its buffer and has a TWAP
    function addSeries(address adapter, uint256 maturity) external {
        if (sSeries[adapter][maturity].status != SeriesStatus.QUEUED) revert Errors.SeriesNotQueued();
        if (zeroParams.irModel == address(0)) revert Errors.ZeroParamsNotSet();
        if (lpTokenParams.irModel == address(0)) revert Errors.PoolParamsNotSet();

        address zero = Divider(divider).zero(adapter, maturity);
        address pool = sSeries[adapter][maturity].pool;

        (, , , , , , uint256 sampleTs) = BalancerOracle(pool).getSample(1023);
        // Prevent this market from being deployed on Fuse if we're able to read a TWAP
        if (sampleTs == 0) revert Errors.OracleNotReady();

        address[] memory underlyings = new address[](2);
        underlyings[0] = zero;
        underlyings[1] = pool;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        oracles[0] = PriceOracle(zeroOracle);
        oracles[1] = PriceOracle(lpOracle);

        ZeroOracle(zeroOracle).setZero(zero, pool);
        MasterOracleLike(masterOracle).add(underlyings, oracles);

        bytes memory constructorDataZero = abi.encode(
            zero,
            comptroller,
            zeroParams.irModel,
            ERC20(zero).name(),
            ERC20(zero).symbol(),
            cERC20Impl,
            hex"",
            zeroParams.reserveFactor,
            0 // no admin fee
        );

        uint256 errZero = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataZero,
            zeroParams.collateralFactor
        );
        if (errZero != 0) revert Errors.FailedAddZeroMarket();

        // LP Share pool token
        bytes memory constructorDataLpToken = abi.encode(
            pool,
            comptroller,
            lpTokenParams.irModel,
            ERC20(pool).name(),
            ERC20(pool).symbol(),
            cERC20Impl,
            hex"",
            lpTokenParams.reserveFactor,
            0 // no admin fee
        );

        uint256 errLpToken = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataLpToken,
            lpTokenParams.collateralFactor
        );
        if (errLpToken != 0) revert Errors.FailedAddLpMarket();

        sSeries[adapter][maturity].status = SeriesStatus.ADDED;

        emit SeriesAdded(zero, pool);
    }

    /* ========== ADMIN ========== */

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "ZERO_PARAMS") zeroParams = data;
        else if (what == "LP_TOKEN_PARAMS") lpTokenParams = data;
        else if (what == "TARGET_PARAMS") targetParams = data;
        else revert Errors.InvalidParam();
        emit ParamsSet(what, data);
    }

    function execute(
        address to,
        uint256 value,
        bytes memory data,
        uint256 txGas
    ) external requiresTrust returns (bool success) {
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /* ========== LOGS ========== */

    event ParamsSet(bytes32 indexed what, AssetParams data);
    event PoolDeployed(string name, address comptroller, uint256 poolIndex, uint256 closeFactor, uint256 liqIncentive);
    event TargetAdded(address indexed target, address indexed cTarget);
    event SeriesQueued(address indexed adapter, uint256 indexed maturity, address indexed pool);
    event SeriesAdded(address indexed zero, address indexed lpToken);
}
