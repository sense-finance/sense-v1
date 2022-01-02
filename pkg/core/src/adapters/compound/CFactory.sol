// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { CropFactory } from "../CropFactory.sol";
import { CAdapter } from "./CAdapter.sol";
import { Divider } from "../../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

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
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, COMPTROLLER, _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool isListed) {
        (isListed, , ) = ComptrollerLike(protocol).markets(_target);
    }

    function deployAdapter(address _target) public virtual override returns (address adapterAddress) {
        CAdapter adapter = new CAdapter(
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
            reward
        );

        _addAdapter(address(adapter));

        return address(adapter);
    }
}
