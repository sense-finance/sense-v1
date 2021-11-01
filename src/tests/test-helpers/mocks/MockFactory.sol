// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CropFactory } from "../../../feeds/CropFactory.sol";

contract MockFactory is CropFactory {
    address public constant ORACLE = address(123);

    mapping(address => bool) public targets;

    constructor(
        address _feedImpl,
        address _divider,
        uint256 _delta,
        address _stake,
        uint256 _issuanceFee,
        uint256 _stakeSize,
        uint256 _minMaturity,
        uint256 _maxMaturity,
        address _reward
    ) CropFactory(
        _divider, address(0), _feedImpl, ORACLE, _stake, _stakeSize,
        _issuanceFee, _minMaturity, _maxMaturity, _delta, _reward
    ) { }

    function _exists(address _target) internal override virtual returns (bool) {
        return targets[_target];
    }

    function addTarget(address _target, bool status) external {
        targets[_target] = status;
    }

}
