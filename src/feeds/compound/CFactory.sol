// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// internal references
import { BaseFactory } from "../BaseFactory.sol";

interface Comptroller {
    function markets(address target) external returns (bool isListed, uint collateralFactorMantissa, bool isComped);
}

contract CFactory is BaseFactory {
    constructor(
        address _implementation,
        address _divider,
        uint256 _delta,
        address _airdropToken
    ) BaseFactory(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B, _implementation, _divider, _delta, _airdropToken) {}

    function _exists(address _target) internal override virtual returns (bool) {
        (bool isListed, , ) = Comptroller(protocol).markets(_target);
        return isListed;
    }
}
