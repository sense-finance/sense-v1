// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory is Trust {
    /* ========== CONSTANTS ========== */

    /// @notice Sets level to `31` by default, which keeps all Divider lifecycle methods public
    /// (`issue`, `combine`, `collect`, etc), but not the `onRedeem` hook.
    uint48 public constant DEFAULT_LEVEL = 31;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice target -> adapter
    mapping(address => address) public adapters;

    /// @notice params for adapters deployed with this factory
    FactoryParams public factoryParams;

    /* ========== DATA STRUCTURES ========== */

    struct FactoryParams {
        address oracle; // oracle address
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
        uint128 ifee; // issuance fee
        uint16 mode; // 0 for monthly, 1 for weekly
        uint64 tilt; // tilt
        // Yieldspace config
        uint256 ts;
        uint256 g1;
        uint256 g2;
        bool oracleEnabled;
    }

    constructor(address _divider, FactoryParams memory _factoryParams) Trust(msg.sender) {
        divider = _divider;
        factoryParams = _factoryParams;
    }

    /* ========== REQUIRED DEPLOY ========== */

    /// @notice Deploys both an adapter and a target wrapper for the given _target
    /// @param _target Address of the Target token
    /// @param _data Additional data needed to deploy the adapter
    function deployAdapter(address _target, bytes memory _data) external virtual returns (address adapter) {}

    /* ========== SPACE SETTERS ========== */

    function setSpaceParams(
        address _adapter,
        uint256 _ts,
        uint256 _g1,
        uint256 _g2,
        bool _oracleEnabled
    ) public requiresTrust {
        BaseAdapter(_adapter).setSpaceParams(_ts, _g1, _g2, _oracleEnabled);
    }

    /* ========== LOGS ========== */

    /// @notice Logs the deployment of the adapter
    event AdapterAdded(address addr, address indexed target);
}
