// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { CropFactory } from "../../../adapters/CropFactory.sol";
import { Divider } from "../../../Divider.sol";
import { MockAdapter } from "./MockAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

contract MockFactory is CropFactory {
    using Bytes32AddressLib for address;

    mapping(address => bool) public targets;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, address(0), _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

    function deployAdapter(address _target) external override returns (address adapterAddress) {
        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a CAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        MockAdapter adapter = new MockAdapter{ salt: _target.fillLast12Bytes() }(
            divider,
            _target,
            factoryParams.oracle,
            factoryParams.delta,
            factoryParams.ifee,
            factoryParams.stake,
            factoryParams.stakeSize,
            factoryParams.minm,
            factoryParams.maxm,
            factoryParams.mode,
            factoryParams.tilt,
            reward
        );

        _addAdapter(address(adapter));

        return address(adapter);
    }
}
