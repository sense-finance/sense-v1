// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
import { BaseFactory } from "../BaseFactory.sol";

interface ComptrollerLike {
    function markets(
        address target
    ) external returns (
        bool isListed, uint collateralFactorMantissa, bool isComped
    );
}

contract CFactory is BaseFactory {
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    constructor(
        address _feedImpl,
        address _twImpl,
        address _divider,
        uint256 _delta,
        address _reward
    ) BaseFactory(COMPTROLLER, _feedImpl, _twImpl, _divider, _delta, _reward) {}

    function _exists(address _target) internal override virtual returns (bool isListed) {
        (isListed, , ) = ComptrollerLike(protocol).markets(_target);
    }
}
