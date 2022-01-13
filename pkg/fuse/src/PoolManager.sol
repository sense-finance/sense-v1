// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External reference
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";
import { PriceOracle } from "./external/PriceOracle.sol";

// Internal references
import { UnderlyingOracle } from "./oracles/Underlying.sol";
import { TargetOracle } from "./oracles/Target.sol";
import { ZeroOracle } from "./oracles/Zero.sol";
import { LPOracle } from "./oracles/LP.sol";

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

    function cTokensByUnderlying(address underlying) external returns (address);
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
    address public immutable comptrollerImpl;
    address public immutable cERC20Impl;
    address public immutable fuseDirectory;
    address public immutable divider;

    address public immutable oracleImpl; // master oracle from Fuse
    address public immutable targetOracle;
    address public immutable zeroOracle;
    address public immutable lpOracle;
    address public immutable underlyingOracle;

    address public comptroller;
    address public masterOracle;

    enum SeriesStatus {
        NONE,
        QUEUED,
        ADDED
    }

    struct AssetParams {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }

    struct Series {
        SeriesStatus status;
        address pool;
    }

    AssetParams public targetParams;
    AssetParams public zeroParams;
    AssetParams public lpTokenParams;

    /// @notice Target Inits: target -> target added to pool
    mapping(address => bool) public tInits;

    /// @notice Series Pools: adapter -> maturity -> (series status (zeros/lp shares), AMM pool)
    mapping(address => mapping(uint256 => Series)) public sSeries;

    event ParamsSet(bytes32 indexed what, AssetParams data);
    event PoolDeployed(string name, address comptroller, uint256 poolIndex, uint256 closeFactor, uint256 liqIncentive);
    event TargetAdded(address indexed target, address indexed cTarget);
    event SeriesAdded(address indexed zero, address indexed lpToken);
    event SeriesQueued(address indexed adapter, uint48 indexed maturity, address indexed pool);

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
        require(comptroller == address(0), Errors.PoolAlreadyDeployed);

        masterOracle = Clones.cloneDeterministic(oracleImpl, Bytes32AddressLib.fillLast12Bytes(address(this)));
        MasterOracleLike(masterOracle).initialize(
            new address[](0),
            new PriceOracle[](0),
            PriceOracle(fallbackOracle),
            address(this),
            true
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
        require(err == 0, Errors.FailedBecomeAdmin);
        comptroller = _comptroller;

        emit PoolDeployed(name, _comptroller, _poolIndex, closeFactor, liqIncentive);
    }

    function addTarget(address target, address adapter) external requiresTrust returns (address cTarget) {
        require(comptroller != address(0), Errors.PoolNotDeployed);
        require(!tInits[target], Errors.TargetExists);
        require(targetParams.irModel != address(0), Errors.PoolParamsNotSet);

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

        uint256 adminFee = 0;
        bytes memory constructorData = abi.encode(
            target,
            comptroller,
            targetParams.irModel,
            ERC20(target).name(),
            ERC20(target).symbol(),
            cERC20Impl,
            hex"", // calldata sent to becomeImplementation (currently unused)
            targetParams.reserveFactor,
            adminFee
        );

        uint256 err = ComptrollerLike(comptroller)._deployMarket(false, constructorData, targetParams.collateralFactor);
        require(err == 0, Errors.FailedAddMarket);

        cTarget = ComptrollerLike(comptroller).cTokensByUnderlying(target);

        tInits[target] = true;
        emit TargetAdded(target, cTarget);
    }

    /// @notice queues a set of (Zero, LPShare) for a  Fuse pool once the TWAP is ready
    /// @dev called by the Periphery, which will know which pool address to set for this Series
    function queueSeries(
        address adapter,
        uint48 maturity,
        address pool
    ) external requiresTrust {
        (address zero, , , , , , , , ) = Divider(divider).series(adapter, maturity);

        require(comptroller != address(0), Errors.PoolNotDeployed);
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(sSeries[adapter][maturity].status == SeriesStatus.NONE, Errors.DuplicateSeries);

        address target = Adapter(adapter).target();
        require(tInits[target], Errors.TargetNotInFuse);

        sSeries[adapter][maturity] = Series({
            status: SeriesStatus.QUEUED,
            pool: pool
        });

        emit SeriesQueued(adapter, maturity, pool);
    }

    /// @notice open method to add queued Zeros and LPShares to Fuse pool
    /// @dev this can only be done once the yield space pool has filled its buffer and has a TWAP
    function addSeries(address adapter, uint48 maturity) external {
        require(sSeries[adapter][maturity].status == SeriesStatus.QUEUED, Errors.SeriesNotQueued);

        require(zeroParams.irModel != address(0), Errors.PoolParamsNotSet);
        require(lpTokenParams.irModel != address(0), Errors.PoolParamsNotSet);

        (address zero, , , , , , , , ) = Divider(divider).series(adapter, maturity);

        address pool = sSeries[adapter][maturity].pool;

        address[] memory underlyings = new address[](2);
        underlyings[0] = zero;
        underlyings[1] = pool;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        oracles[0] = PriceOracle(zeroOracle);
        oracles[1] = PriceOracle(lpOracle);

        ZeroOracle(zeroOracle).setZero(zero, pool);
        MasterOracleLike(masterOracle).add(underlyings, oracles);

        uint256 adminFee = 0;
        bytes memory constructorDataZero = abi.encode(
            zero,
            comptroller,
            zeroParams.irModel,
            ERC20(zero).name(),
            ERC20(zero).symbol(),
            cERC20Impl,
            hex"",
            zeroParams.reserveFactor,
            adminFee
        );

        uint256 errZero = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataZero,
            zeroParams.collateralFactor
        );
        require(errZero == 0, Errors.FailedAddZeroMarket);

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
            adminFee
        );

        uint256 errLpToken = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataLpToken,
            lpTokenParams.collateralFactor
        );
        require(errLpToken == 0, Errors.FailedAddLPMarket);

        sSeries[adapter][maturity].status = SeriesStatus.ADDED;

        emit SeriesAdded(zero, pool);
    }

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "ZERO_PARAMS") zeroParams = data;
        else if (what == "LP_TOKEN_PARAMS") lpTokenParams = data;
        else if (what == "TARGET_PARAMS") targetParams = data;
        else revert("Invalid param");
        emit ParamsSet(what, data);
    }
}
