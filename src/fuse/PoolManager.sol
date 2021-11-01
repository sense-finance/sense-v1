// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External reference
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";
import { PriceOracle } from "../external/fuse/PriceOracle.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";
import { Errors } from "../libs/Errors.sol";
import { Token } from "../tokens/Token.sol";

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
}

interface MasterOracleLike {
    function initialize(
        address[] memory underlyings, 
        PriceOracle[] memory _oracles, 
        PriceOracle _defaultOracle, 
        address _admin, 
        bool _canAdminOverwrite
    ) external;
    function add(
        address[] calldata underlyings, 
        PriceOracle[] calldata _oracles
    ) external;
}

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    address public immutable comptrollerImpl;
    address public immutable cERC20Impl;
    address public immutable fuseDirectory;
    address public immutable divider;
    address public immutable gClaimManager;
    address public immutable oracleImpl;
    address public comptroller;
    address public masterOracle;

    struct AssetParams {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }

    AssetParams public zeroParams;
    AssetParams public claimParams;
    AssetParams public lpShareParams;
    AssetParams public targetParams;

    /// @notice Target Inits: target -> target added to pool
    mapping(address => bool) public tInits;
    /// @notice Series Inits: feed -> maturity -> series (zerosclaims) added to pool
    mapping(address => mapping(uint256 => bool)) public sInits;

    event SetParams(bytes32 indexed what, AssetParams data);
    event PoolDeployed(
        string name,
        address comptroller,
        uint256 poolIndex,
        uint256 closeFactor,
        uint256 liqIncentive
    );
    event TargetAdded(address target);
    event SeriesAdded(address zero, address claim);

    constructor(
        address _fuseDirectory,
        address _comptrollerImpl,
        address _cERC20Impl,
        address _divider,
        address _oracleImpl,
        address _gClaimManager
    ) Trust(msg.sender) {
        fuseDirectory   = _fuseDirectory;
        comptrollerImpl = _comptrollerImpl;
        cERC20Impl = _cERC20Impl;
        divider    = _divider;
        oracleImpl = _oracleImpl; // master oracle
        gClaimManager = _gClaimManager;
    }

    function deployPool(
        string calldata name,
        uint256 closeFactor,
        uint256 liqIncentive,
        address fallbackOracle
    ) external requiresTrust returns (uint256 _poolIndex, address _comptroller) {
        require(comptroller == address(0), "Pool already deployed");

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
            false, // whitelist is always false
            closeFactor,
            liqIncentive,
            masterOracle
        );

        uint256 err = ComptrollerLike(_comptroller)._acceptAdmin();
        require(err == 0, "Failed to become admin");
        comptroller = _comptroller;

        emit PoolDeployed(name, _comptroller, _poolIndex, closeFactor, liqIncentive);
    }

    function addTarget(address target, address targetOracle) external requiresTrust {
        require(comptroller != address(0), "Pool not yet deployed");
        require(!tInits[target], "Target already added");
        require(targetParams.irModel != address(0), "Target asset params not set");

        address[] memory underlyings = new address[](1);
        underlyings[0] = target;

        PriceOracle[] memory oracles = new PriceOracle[](1);
        oracles[0] = PriceOracle(targetOracle);

        MasterOracleLike(masterOracle).add(underlyings, oracles);

        uint256 adminFee = 0;
        bytes memory constructorData = abi.encode(
            target,
            comptroller,
            targetParams.irModel,
            Token(target).name(),
            Token(target).symbol(),
            cERC20Impl,
            "0x00", // calldata sent to becomeImplementation (currently unused)
            targetParams.reserveFactor,
            adminFee
        );

        uint256 err = ComptrollerLike(comptroller)._deployMarket(false, constructorData, targetParams.collateralFactor);
        require(err == 0, "Failed to add market");

        // TODO: get actual cTarget address

        tInits[target] = true;
        emit TargetAdded(target);
    }

    function addSeries(address feed, uint256 maturity) external requiresTrust {
        (address zero, address claim, , , , , , , ) = Divider(divider).series(feed, maturity);

        require(comptroller != address(0), "Pool not yet deployed");
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(!sInits[feed][maturity], Errors.DuplicateSeries);

        address target = Feed(feed).target();
        require(tInits[target], "Target for this Series not yet added");

        // TODO: lp shares

        address[] memory underlyings = new address[](2);
        underlyings[0] = zero;
        underlyings[1] = claim;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        // TODO: proper oracles using lp shares
        oracles[0] = PriceOracle(address(0));
        oracles[1] = PriceOracle(address(0));

        MasterOracleLike(masterOracle).add(underlyings, oracles);

        uint256 adminFee = 0;
        bytes memory constructorDataZero = abi.encodePacked(
            zero,
            comptroller,
            zeroParams.irModel,
            Token(zero).name(),
            Token(zero).symbol(),
            cERC20Impl,
            "0x00", // calldata sent to becomeImplementation (currently unused)
            zeroParams.reserveFactor,
            adminFee
        );
        bytes memory constructorDataClaim = abi.encodePacked(
            claim,
            comptroller,
            claimParams.irModel,
            Token(claim).name(),
            Token(claim).symbol(),
            cERC20Impl,
            "0x00", // calldata sent to becomeImplementation (currently unused)
            claimParams.reserveFactor,
            adminFee
        );

        uint256 errZero = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataZero,
            zeroParams.collateralFactor
        );
        require(errZero == 0, "Failed to add market");

        uint256 errClaim = ComptrollerLike(comptroller)._deployMarket(
            false,
            constructorDataClaim,
            claimParams.collateralFactor
        );
        require(errClaim == 0, "Failed to add market");

        sInits[feed][maturity] = true;
    }

    // TODO pause/delist

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "ZERO_PARAMS") zeroParams = data;
        else if (what == "CLAIM_PARAMS") claimParams = data;
        else if (what == "LP_SHARE_PARAMS") lpShareParams = data;
        else if (what == "TARGET_PARAMS") targetParams = data;
        else revert("Invalid param");
        emit SetParams(what, data);
    }
}
