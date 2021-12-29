// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolFactory } from "@balancer-labs/v2-pool-utils/contracts/factories/BasePoolFactory.sol";
import { IVault } from "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";

import { Space } from "./Space.sol";

interface DividerLike {
    function series(
        address, /* adapter */
        uint256 /* maturity */
    )
        external
        returns (
            address, /* zero */
            address, /* claim */
            address, /* sponsor */
            uint256, /* reward */
            uint256, /* iscale */
            uint256, /* mscale */
            uint256, /* maxscale */
            uint128, /* issuance */
            uint128 /* tilt */
        );
}

contract SpaceFactory is Trust {

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Balancer Vault
    IVault public immutable vault;

    /// @notice Sense Divider ᗧ···ᗣ···ᗣ··
    address public immutable divider;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    /// @notice Pool registry (adapter -> maturity -> pool address)
    mapping(address => mapping(uint256 => address)) public pools;

    /// @notice Yieldspace config
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

    /// @notice Deploys a new `Space` contract
    function create(address _adapter, uint48 _maturity) external returns (address) {
        require(pools[_adapter][_maturity] == address(0), "POOL_ALREADY_EXISTS");

        (address zero, , , , , , , , ) = DividerLike(divider).series(_adapter, uint256(_maturity));
        address pool = address(new Space(vault, _adapter, _maturity, zero, ts, g1, g2));

        pools[_adapter][_maturity] = pool;
        return pool;
    }
    
    function setParams(
        uint256 _ts,
        uint256 _g1,
        uint256 _g2
    ) public requiresTrust {
        // g1 is for swapping Targets to Zeros and should discount the effective interest 
        require(_g1 <= FixedPoint.ONE, "INVALID_G1");
        // g2 is for swapping Zeros to Target and should mark the effective interest up
        require(_g2 >= FixedPoint.ONE, "INVALID_G2");

        ts = _ts;
        g1 = _g1;
        g2 = _g2;
    }
}
