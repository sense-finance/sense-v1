// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { Divider } from "../Divider.sol";

abstract contract BaseFactory {
    address public immutable divider;
    address public immutable protocol; // protocol's data contract address
    address public immutable adapterImpl; // adapter implementation

    event AdapterDeployed(address addr, address indexed target);
    event DeltaChanged(uint256 delta);
    event AdapterImplementationChanged(address implementation);
    event ProtocolChanged(address protocol);

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
        address _adapterImpl,
        FactoryParams memory _factoryParams
    ) {
        divider = _divider;
        protocol = _protocol;
        adapterImpl = _adapterImpl;
        factoryParams = _factoryParams;
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
            delta: factoryParams.delta,
            oracle: factoryParams.oracle,
            ifee: factoryParams.ifee,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode
        });
        BaseAdapter(adapterClone).initialize(divider, adapterParams);

        // authd set adapter since this adapter factory is only for Sense-vetted adapters
        Divider(divider).setAdapter(adapterClone, true);

        emit AdapterDeployed(adapterClone, _target);

        return adapterClone;
    }

    /* ========== INTERNAL ========== */

    /// @notice Target validity check that must be overriden by child contracts
    function _exists(address _target) internal virtual returns (bool);
}
