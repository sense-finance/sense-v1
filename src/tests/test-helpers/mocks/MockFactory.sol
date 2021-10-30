// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { BaseFactory } from "../../../feeds/BaseFactory.sol";

contract MockFactory is BaseFactory {
    mapping(address => bool) public targets;

    constructor(
        address _feedImpl,
        address _twImpl,
        address _divider,
        uint256 _delta,
        address _reward,
        address _stake,
        uint256 _issuanceFee,
        uint256 _initStake,
        uint256 _minMaturity,
        uint256 _maxMaturity
    ) BaseFactory(address(0), _feedImpl, _twImpl, _divider, _delta, _reward, _stake, _issuanceFee, _initStake, _minMaturity, _maxMaturity) {}

    function _exists(address _target) internal override virtual returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

}
