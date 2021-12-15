// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory {
    using Bytes32AddressLib for address;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Protocol's data contract address
    address public immutable protocol;
    
    FactoryParams public factoryParams;
    struct FactoryParams {
        address oracle; // oracle address
        uint256 delta; // max growth per second allowed
        uint256 ifee; // issuance fee
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
        uint8 mode; // 0 for monthly, 1 for weekly
    }

    FactoryParams public factoryParams;
    struct FactoryParams {
        address oracle; // oracle address
        uint256 delta; // max growth per second allowed
        uint256 ifee; // issuance fee
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
        uint8 mode; // 0 for monthly, 1 for weekly
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

    /* ========== REQUIRED DEPLOY ========== */

    /// @notice Deploys both a adapter and a target wrapper for the given _target
    /// @param _target Address of the Target token
    function deployAdapter(address _target) external virtual returns (address adapter);

    /* ========== REQUIRED INTERNAL GUARD ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);

    /* ========== LOGS ========== */

    /// @notice Logs the deployment of the adapter
    event AdapterDeployed(address addr, address indexed target);
}