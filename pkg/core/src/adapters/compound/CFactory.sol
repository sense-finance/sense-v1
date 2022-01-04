// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { CropFactory } from "../CropFactory.sol";

interface ComptrollerLike {
    function markets(address target)
        external
        returns (
            bool isListed,
            uint256 collateralFactorMantissa,
            bool isComped
        );

    function oracle() external returns (address);
}

contract CFactory is CropFactory {
    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    constructor(
        address _divider,
        address _adapterImpl,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, COMPTROLLER, _adapterImpl, _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool isListed) {
        (isListed, , ) = ComptrollerLike(protocol).markets(_target);
    }
}
