// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "../libs/Errors.sol";
import { CropFeed } from "./CropFeed.sol";
import { BaseFeed } from "./BaseFeed.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public immutable reward;

    constructor(
        address _divider,
        address _protocol,
        address _feedImpl,
        address _stake,
        uint256 _stakeSize,
        uint256 _issuanceFee,
        uint256 _minMaturity,
        uint256 _maxMaturity,
        uint256 _delta,
        address _reward
    ) BaseFactory(
        _divider, _protocol, _feedImpl, _stake, _stakeSize, 
        _issuanceFee, _minMaturity, _maxMaturity, _delta
    ) {
        reward = _reward;
    }

    function deployFeed(address _target) external override returns (address feedClone) {
        require(_exists(_target), Errors.NotSupported);

        feedClone = Clones.cloneDeterministic(feedImpl, Bytes32AddressLib.fillLast12Bytes(_target));
        BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
            target: _target,
            delta: delta,
            ifee: issuanceFee,
            stake: stake,
            stakeSize: stakeSize,
            minm: minMaturity,
            maxm: maxMaturity
        });

        CropFeed(feedClone).initialize(divider, feedParams, reward);
        Divider(divider).setFeed(feedClone, true);

        emit FeedDeployed(feedClone);

        return feedClone;
    }
}