// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { Divider } from "../Divider.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

/// @title Fuse Pool Manager
/// @notice Consolidated Fuse interactions
contract PoolManager is Trust {
    address public immutable comptroller;
    address public immutable divider;

    struct Params {
        address irModel;
        uint256 reserveFactor;
        uint256 collateralFactor;
        uint256 closeFactor;
        uint256 liquidationIncentive;
    }

    constructor(address _comptroller, address _divider) Trust(msg.sender) {
        comptroller = _comptroller;
        divider     = _divider;
        // Deploy pool
    }

    function init(address feed, uint256 maturity) external {
        // require Series to exist

        // Create pool for this series with:
        // * Zeros
        // * Claims
        // * Target

        // Init each assset with the configured risk params
        
    }

    function stop(address feed, uint256 maturity) external {
        // require Series to exist  
        require(isTrusted[msg.sender]); // is trusted OR series has already been settled

        // Unset assets from Series in the pool

    }

    function setParams() external {
        // Params include:
        // * Interest rate model
        // * Reserve factor
        // * Collateral factor
        // * Close Factor
        // * Liquidation Incentive
    }

    // risk params, IR models
}
