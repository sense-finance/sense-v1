// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/Errors.sol";
import { CropAdapter } from "./CropAdapter.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public immutable reward;

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
        uint256 _delta,
        address _reward
    )
        BaseFactory(
            _divider,
            _protocol,
            _adapterImpl,
            _oracle,
            _stake,
            _stakeSize,
            _issuanceFee,
            _minMaturity,
            _maxMaturity,
            _delta
        )
    {
        reward = _reward;
    }

    function deployAdapter(address _target) external override returns (address adapterClone) {
        require(_exists(_target), Errors.NotSupported);

        adapterClone = Clones.cloneDeterministic(adapterImpl, Bytes32AddressLib.fillLast12Bytes(_target));
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

        CropAdapter(adapterClone).initialize(divider, adapterParams, reward);
        Divider(divider).setAdapter(adapterClone, true);

        emit AdapterDeployed(adapterClone);

        return adapterClone;
    }
}
