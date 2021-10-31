// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CropFactory } from "../CropFactory.sol";

interface ComptrollerLike {
    function markets(
        address target
    ) external returns (
        bool isListed, uint collateralFactorMantissa, bool isComped
    );
    function oracle() external returns (address);
}

contract CFactory is CropFactory {
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

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
    ) CropFactory(
        _divider, COMPTROLLER, _feedImpl, ComptrollerLike(COMPTROLLER).oracle(), _stake, _stakeSize,
        _issuanceFee, _minMaturity, _maxMaturity, _delta, _reward
    ) { }

    function _exists(address _target) internal override virtual returns (bool isListed) {
        (isListed, , ) = ComptrollerLike(protocol).markets(_target);
    }
}
