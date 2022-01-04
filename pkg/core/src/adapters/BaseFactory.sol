// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory {
    /* ========== CONSTANTS ========== */

    /// @notice Sets level to `7` by default, which enables all Divider lifecycle methods
    /// (`issue`, `combine`, `collect`), but not the `onZeroRedeem` hook.
    uint16 public constant DEFAULT_LEVEL = 7;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Protocol's data contract address
    address public immutable protocol;

    /// @notice target -> adapter
    mapping(address => address) public adapters;

    FactoryParams public factoryParams;
    struct FactoryParams {
        address oracle; // oracle address
        uint64 ifee; // issuance fee
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint48 minm; // min maturity (seconds after block.timstamp)
        uint48 maxm; // max maturity (seconds after block.timstamp)
        uint16 mode; // 0 for monthly, 1 for weekly
        uint64 tilt; // tilt
    }

    constructor(
        address _divider,
        address _protocol,
        FactoryParams memory _factoryParams
    ) {
        divider = _divider;
        protocol = _protocol;
        factoryParams = _factoryParams;
    }

    /// @notice Performs sanity checks and adds the adapter to Divider
    /// @param _adapter Address of the adapter
    function _addAdapter(address _adapter) internal {
        address target = BaseAdapter(_adapter).target();
        require(_exists(target), Errors.NotSupported);
        Divider(divider).setAdapter(address(_adapter), true);
        emit AdapterAdded(address(_adapter), target);
    }

    /* ========== REQUIRED DEPLOY ========== */

    /// @notice Deploys both an adapter and a target wrapper for the given _target
    /// @param _target Address of the Target token
    /// @dev Must call _addAdapter()
    function deployAdapter(address _target) external virtual returns (address adapter) {}

    /* ========== REQUIRED INTERNAL GUARD ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);

    /* ========== LOGS ========== */

    /// @notice Logs the deployment of the adapter
    event AdapterAdded(address addr, address indexed target);
}
