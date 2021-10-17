// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External reference
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";
import { Errors } from "../libs/errors.sol";
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
        uint collateralFactorMantissa
    ) external returns (uint256);
    function _acceptAdmin() external returns (uint256);
    function admin() external returns (address);
    function getAllMarkets() external returns (CTokenLike[] memory);

}

interface CTokenLike {}

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    address public immutable comptrollerImpl;
    address public immutable cERC20Iml;
    address public immutable fuseDirectory;
    address public immutable divider;
    address public immutable oracle;
    address public comptroller;

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

    mapping(address => bool) public tInits; // Target Inits: target -> target added to pool
    mapping(address => mapping(uint256 => bool)) public sInits; // Series Inits: feed -> maturity -> series (zerosclaims) added to pool

    event SetParams(bytes32 indexed what, AssetParams data);
    event PoolDeployed(
        string name, address comptrollerImpl, address comptroller, uint256 poolIndex,
        bool whitelist, uint256 closeFactor, uint256 liqIncentive, address oracle
    );
    event TargetAdded(address target, address cTarget);
    event SeriesAdded(address zero, address claim, address cZero, address cClaim);

    constructor(address _fuseDirectory, address _comptrollerImpl, address _cERC20Iml, address _divider, address _oracle) Trust(msg.sender) {
        fuseDirectory   = _fuseDirectory;
        comptrollerImpl = _comptrollerImpl;
        cERC20Iml       = _cERC20Iml;
        divider         = _divider;
        oracle          = _oracle; // Master oracle contract
    }

    function deployPool(
        string calldata name, bool whitelist, uint256 closeFactor, 
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
        emit PoolDeployed(name, comptrollerImpl, _comptroller, _poolIndex, whitelist, closeFactor, liqIncentive, oracle);
    }

    event A(address);
    event B(bytes);
    function addTarget(address target, address feed, uint256 maturity) external {
        // Pass in a (feed, maturity) pair so that we can verify that this a Target is being used in a Series
        (address zero, , , , , , ) = Divider(divider).series(feed, maturity);

        require(comptroller != address(0), "Pool not yet deployed");
        require(zero != address(0), Errors.SeriesDoesntExists);

        require(target == Feed(feed).target(), "Target is a valid");
        require(!tInits[target], "Target already added");
        require(targetParams.irModel != address(0), "Target asset params not set");

        uint256 adminFee = 0;
        bytes memory constructorData = abi.encode(
            target, 
            comptroller, 
            targetParams.irModel, 
            Token(target).name(),
            Token(target).symbol(),
            cERC20Iml,
            "0x00", // calldata sent to becomeImplementation (currently unused)
            targetParams.reserveFactor,
            adminFee
        );

        uint256 err = ComptrollerLike(comptroller)._deployMarket(false, constructorData, targetParams.collateralFactor);
        require(err == 0, "Failed to add market");

        // CTokenLike[] memory cTokens = ComptrollerLike(comptroller).getAllMarkets();
        // cTokens[cTokens.length - 1];

        // register on oracle

        tInits[target] = true;
        emit TargetAdded(target, target);
    }

    function addSeries(address feed, uint256 maturity) external {
        (address zero, address claim, , , , , ) = Divider(divider).series(feed, maturity);

        require(comptroller != address(0), "Pool not yet deployed");
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(!sInits[feed][maturity], Errors.DuplicateSeries);

        address target = Feed(feed).target();
        require(tInits[target], "Target for this Series not yet added");

        uint256 adminFee = 0;
        bytes memory constructorDataZero = abi.encodePacked(
                zero, 
                comptroller, 
                zeroParams.irModel, 
                Token(zero).name(),
                Token(zero).symbol(),
                cERC20Iml,
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
                cERC20Iml,
                "0x00", // calldata sent to becomeImplementation (currently unused)
                claimParams.reserveFactor,
                adminFee
        );

        uint256 errZero = ComptrollerLike(comptroller)._deployMarket(false, constructorDataZero, zeroParams.collateralFactor);
        require(errZero == 0, "Failed to add market");

        uint256 errClaim = ComptrollerLike(comptroller)._deployMarket(false, constructorDataClaim, claimParams.collateralFactor);
        require(errClaim == 0, "Failed to add market");

        sInits[feed][maturity] = true;
    }

    // function pauseTarget(address feed, uint256 maturity) external {
        // require Series to exist  
        // require(isTrusted[msg.sender]); // is trusted OR series has already been settled

        // _setMintPaused

        // _setBorrowPaused

        // Unset assets from Series in the pool

    // }


    // function pauseSeries(address feed, uint256 maturity) external {
        // require Series to exist  
        // require(isTrusted[msg.sender]); // is trusted OR series has already been settled

        // _setMintPaused

        // _setBorrowPaused

        // Unset assets from Series in the pool

    // }

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "ZERO_PARAMS") zeroParams = data;
        else if (what == "CLAIM_PARAMS") claimParams = data;
        else if (what == "TARGET_PARAMS") targetParams = data;
        else revert("Invalid param");
        emit SetParams(what, data);
    }
}