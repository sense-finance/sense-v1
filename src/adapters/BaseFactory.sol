// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Errors } from "../libs/Errors.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory is Trust {
    address public immutable divider;
    address public immutable protocol; // protocol's data contract address
    address public immutable adapterImpl; // adapter implementation
    address public immutable oracle;
    address public immutable stake;
    uint256 public immutable stakeSize;
    uint256 public immutable issuanceFee;
    uint256 public immutable minMaturity;
    uint256 public immutable maxMaturity;
    uint256 public delta;

    event AdapterDeployed(address addr);
    event DeltaChanged(uint256 delta);
    event AdapterImplementationChanged(address implementation);
    event ProtocolChanged(address protocol);

    constructor(
        address _divider,
        address _protocol,
        address _adapterImpl,
        address _oracle,
        address _stake,
        uint256 _stakeSize,
        uint256 _issuanceFee,
        uint256 _minMaturity,
        uint256 _maxMaturity,
        uint256 _delta
    ) Trust(msg.sender) {
        divider = _divider;
        protocol = _protocol;
        adapterImpl = _adapterImpl;
        oracle = _oracle;
        stake = _stake;
        stakeSize = _stakeSize;
        issuanceFee = _issuanceFee;
        minMaturity = _minMaturity;
        maxMaturity = _maxMaturity;
        delta = _delta;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deploys both a adapter and a target wrapper for the given _target
    /// @param _target Address of the Target token
    function deployAdapter(address _target) external virtual returns (address adapterClone) {
        require(_exists(_target), Errors.NotSupported);

        // clone the adapter using the Target address as salt
        // note: duplicate Target addresses will revert
        adapterClone = Clones.cloneDeterministic(adapterImpl, Bytes32AddressLib.fillLast12Bytes(_target));

        // TODO: see if we can inline this
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: _target,
            delta: delta,
            oracle: oracle,
            ifee: issuanceFee,
            stake: stake,
            stakeSize: stakeSize,
            minm: minMaturity,
            maxm: maxMaturity
        });
        BaseAdapter(adapterClone).initialize(divider, adapterParams);

        // authd set adapter since this adapter factory is only for Sense-vetted adapters
        Divider(divider).setAdapter(adapterClone, true);

        emit AdapterDeployed(adapterClone);

        return adapterClone;
    }

    /* ========== ADMIN ========== */

    function setDelta(uint256 _delta) external requiresTrust {
        delta = _delta;
        emit DeltaChanged(_delta);
    }

    /* ========== INTERNAL ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);
}
