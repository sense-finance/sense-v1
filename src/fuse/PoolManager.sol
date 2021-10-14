// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External reference
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";
import { Errors } from "../libs/errors.sol";

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

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    address public immutable comptrollerImpl;
    address public immutable fuseDirectory;
    address public immutable divider;
    address public immutable oracle;

    struct AssetParams {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }

    bool public deployed;
    AssetParams public zeros;
    AssetParams public claims;
    AssetParams public target;
    mapping(address => mapping(uint256 => bool)) public inits;

    /// @notice Events
    event SetParams(bytes32 indexed what, AssetParams data);
    event PoolDeployed(
        string name, address comptrollerImpl, bool whitelist, 
        uint256 closeFactor, uint256 liqIncentive, address oracle
    );

    constructor(address _fuseDirectory, address _comptrollerImpl, address _divider, address _oracle) Trust(msg.sender) {
        fuseDirectory   = _fuseDirectory;
        comptrollerImpl = _comptrollerImpl;
        divider         = _divider;
        oracle          = _oracle;
    }

    function deployPool(string calldata name, bool whitelist, uint256 closeFactor, uint256 liqIncentive) external requiresTrust {
        require(!deployed, "Pool already deployed");

        FuseDirectoryLike(fuseDirectory).deployPool(
            name,
            comptrollerImpl,
            whitelist,  
            closeFactor,
            liqIncentive,
            oracle  
        );

        deployed = true;

        emit PoolDeployed(name, comptrollerImpl, whitelist, closeFactor,liqIncentive, oracle);
    }

    function initAssets(address feed, uint256 maturity) external {
        (address zero, address claim, , , , , ) = Divider(divider).series(feed, maturity);
        address target = Feed(feed).target();

        require(deployed, "Pool not yet deployed");
        require(zero != address(0), Errors.SeriesDoesntExists);
        require(!inits[feed][maturity], Errors.DuplicateSeries);


        // Create pool for this series with:
        // * Zeros
        // * Claims
        // * Target

        // register on oracle


        // Init each assset with the configured risk params
        inits[feed][maturity] = true;
    }

    function stop(address feed, uint256 maturity) external {
        // require Series to exist  
        require(isTrusted[msg.sender]); // is trusted OR series has already been settled

        // Unset assets from Series in the pool

    }

    function setParams(bytes32 what, AssetParams calldata data) external requiresTrust {
        if (what == "zeros") zeros = data;
        else if (what == "claims") claims = data;
        else if (what == "target") target = data;
        else revert("Invalid param");
        emit SetParams(what, data);
    }
}