// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

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

    AssetParams public targetParams;
    AssetParams public zeroParams;
    AssetParams public lpTokenParams;

    /// @notice Target Inits: target -> target added to pool
    mapping(address => bool) public tInits;

    /// @notice Series Status: adapter -> maturity -> series status (zeros/lp shares)
    mapping(address => mapping(uint256 => SeriesStatus)) public sStatus;

    /// @notice Series Pools: adapter -> maturity -> AMM pool
    mapping(address => mapping(uint256 => address)) public sPools;

    event ParamsSet(bytes32 indexed what, AssetParams data);
    event PoolDeployed(string name, address comptroller, uint256 poolIndex, uint256 closeFactor, uint256 liqIncentive);
    event TargetAdded(address target, address cToken);
    event SeriesAdded(address zero, address lpToken);
    event SeriesQueued(address adapter, uint48 maturity, address pool);

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

    function addTarget(address target, address adapter) external requiresTrust returns (address cToken) {
        require(comptroller != address(0), Errors.PoolNotDeployed);
        require(!tInits[target], Errors.TargetExists);
        require(targetParams.irModel != address(0), Errors.TargetParamNotSet);

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
            "0x00", // calldata sent to becomeImplementation (currently unused)
            targetParams.reserveFactor,
            adminFee
        );

        uint256 err = ComptrollerLike(comptroller)._deployMarket(false, constructorData, targetParams.collateralFactor);
        require(err == 0, Errors.FailedAddMarket);

        cToken = ComptrollerLike(comptroller).cTokensByUnderlying(target);

        tInits[target] = true;
        emit TargetAdded(target, cToken);
    }

    /// @notice queues a set of (Zero, LPShare) fora  Fuse pool once the TWAP is ready
    /// @dev called by the Periphery, which will know which pool address to set for this Series
    function queueSeries(
        address adapter,
        uint48 maturity,
        address pool
    ) external requiresTrust {
        (address zero, , , , , , , , ) = Divider(divider).series(adapter, maturity);

        require(comptroller != address(0), Errors.PoolNotDeployed);
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(sStatus[adapter][maturity] != SeriesStatus.QUEUED, Errors.DuplicateSeries);

        address target = Adapter(adapter).getTarget();
        require(tInits[target], Errors.TargetNotInFuse);

        sStatus[adapter][maturity] = SeriesStatus.QUEUED;
        sPools[adapter][maturity] = pool;

        emit SeriesQueued(adapter, maturity, pool);
    }

    /// @notice open method to add queued Zeros and LPShares to Fuse pool
    /// @dev this can only be done once the yield space pool has filled its buffer and has a TWAP
    function addSeries(address adapter, uint48 maturity) external {
        require(sStatus[adapter][maturity] == SeriesStatus.QUEUED, Errors.SeriesNotQueued);

        (address zero, , , , , , , , ) = Divider(divider).series(adapter, maturity);

        address pool = sPools[adapter][maturity];

        address[] memory underlyings = new address[](2);
        underlyings[0] = zero;
        underlyings[1] = pool;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        oracles[0] = PriceOracle(zeroOracle);
        oracles[1] = PriceOracle(lpOracle);

        ZeroOracle(zeroOracle).setZero(zero, pool);
        MasterOracleLike(masterOracle).add(underlyings, oracles);

        uint256 adminFee = 0;
        bytes memory constructorDataZero = abi.encodePacked(
            zero,
            comptroller,
            zeroParams.irModel,
            ERC20(zero).name(),
            ERC20(zero).symbol(),
            cERC20Impl,
            "0x00",
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
        bytes memory constructorDataLpToken = abi.encodePacked(
            pool,
            comptroller,
            lpTokenParams.irModel,
            ERC20(pool).name(),
            ERC20(pool).symbol(),
            cERC20Impl,
            "0x00",
            lpTokenParams.reserveFactor,
            adminFee
        );

        uint256 errLpToken = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataLpToken,
            lpTokenParams.collateralFactor
        );
        require(errLpToken == 0, Errors.FailedAddLPMarket);

        sStatus[adapter][maturity] = SeriesStatus.ADDED;

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
