// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { BasePoolFactory } from "@balancer-labs/v2-pool-utils/contracts/factories/BasePoolFactory.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

import { Space } from "./Space.sol";

contract SpaceFactory is Trust {
    // Immutables
    IVault public immutable vault;
    address public immutable divider;
    // Pool registry
    mapping(address => mapping(uint256 => address)) public pools;

    // Pool config ---
    uint256 public ts;
    uint256 public g1;
    uint256 public g2;

    constructor(
        IVault _vault,
        address _divider,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) Trust(msg.sender) {
        vault = _vault;
        divider = _divider;
        ts = _ts;
        g1 = _g1;
        g2 = _g2;
    }

    /// @dev Deploys a new `Space` contract
    function create(address _adapter, uint48 _maturity) external returns (address) {
        require(pools[_adapter][_maturity] == address(0), "Space already exists for this Series");

        address pool = address(new Space(vault, _adapter, _maturity, divider, ts, g1, g2));

        pools[_adapter][_maturity] = pool;
        return pool;
    }

    function setParams(
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) public requiresTrust {
        ts = _ts;
        g1 = _g1;
        g2 = _g2;
    }
}
