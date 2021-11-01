// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External reference
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { BaseAdapter as Adapter } from "../adapters/BaseAdapter.sol";
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

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    address public immutable comptrollerImpl;
    address public immutable cERC20Impl;
    address public immutable fuseDirectory;
    address public immutable divider;
    address public immutable oracle;
    address public comptroller;
    address public periphery;

    struct AssetParams {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }
    AssetParams public zeroParams;
    AssetParams public claimParams;
    AssetParams public targetParams;

    /// @notice Target Inits: target -> target added to pool
    mapping(address => bool) public tInits;
    /// @notice Series Inits: adapter -> maturity -> series (zerosclaims) added to pool
    mapping(address => mapping(uint256 => bool)) public sInits;

    event SetParams(bytes32 indexed what, AssetParams data);
    event PoolDeployed(
        string name,
        address comptrollerImpl,
        address comptroller,
        uint256 poolIndex,
        bool whitelist,
        uint256 closeFactor,
        uint256 liqIncentive,
        address oracle
    );
    event TargetAdded(address target, address cTarget);
    event SeriesAdded(address zero, address claim, address cZero, address cClaim);
    event PeripheryChanged(address periphery);

    constructor(
        address _fuseDirectory,
        address _comptrollerImpl,
        address _cERC20Impl,
        address _divider,
        address _oracle
    ) Trust(msg.sender) {
        fuseDirectory = _fuseDirectory;
        comptrollerImpl = _comptrollerImpl;
        cERC20Impl = _cERC20Impl;
        divider = _divider;
        oracle = _oracle; // master oracle
    }

    function deployPool(
        string calldata name,
        bool whitelist,
        uint256 closeFactor,
        uint256 liqIncentive
    ) external requiresTrust returns (uint256 _poolIndex, address _comptroller) {
        require(comptroller == address(0), "Pool already deployed");
        (_poolIndex, _comptroller) = FuseDirectoryLike(fuseDirectory).deployPool(
            name,
            comptrollerImpl,
            whitelist,
            closeFactor,
            liqIncentive,
            oracle
        );

        uint256 err = ComptrollerLike(_comptroller)._acceptAdmin();
        require(err == 0, "Failed to become admin");
        comptroller = _comptroller;

        emit PoolDeployed(
            name,
            comptrollerImpl,
            _comptroller,
            _poolIndex,
            whitelist,
            closeFactor,
            liqIncentive,
            oracle
        );
    }

    function addTarget(address target) external onlyPeriphery {
        require(comptroller != address(0), "Pool not yet deployed");
        require(!tInits[target], "Target already added");
        require(targetParams.irModel != address(0), "Target asset params not set");

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

        // Will use univ3 price oracle on underlying for the Target

        tInits[target] = true;
        emit TargetAdded(target, target);
    }

    function addSeries(address adapter, uint256 maturity) external onlyPeriphery {
        (address zero, address claim, , , , , , , ) = Divider(divider).series(adapter, maturity);

        require(comptroller != address(0), "Pool not yet deployed");
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(!sInits[adapter][maturity], Errors.DuplicateSeries);

        address target = Adapter(adapter).getTarget();
        require(tInits[target], "Target for this Series not yet added");

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

        // Will use univ3 price oracle on these assets

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

        sInits[adapter][maturity] = true;
    }

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "ZERO_PARAMS") zeroParams = data;
        else if (what == "CLAIM_PARAMS") claimParams = data;
        else if (what == "TARGET_PARAMS") targetParams = data;
        else revert("Invalid param");
        emit SetParams(what, data);
    }

    function setPeriphery(address _periphery) external requiresTrust {
        periphery = _periphery;
        emit PeripheryChanged(_periphery);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPeriphery() {
        require(periphery == msg.sender, Errors.OnlyPeriphery);
        _;
    }
}
