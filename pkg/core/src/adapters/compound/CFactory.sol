// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { CropFactory } from "../CropFactory.sol";
import { CAdapter } from "./CAdapter.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

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
    using Bytes32AddressLib for address;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    constructor(
        address _divider,
        FactoryParams memory _factoryParams,
        address _reward
    ) CropFactory(_divider, COMPTROLLER, _factoryParams, _reward) {}

    function _exists(address _target) internal virtual override returns (bool isListed) {
        (isListed, , ) = ComptrollerLike(protocol).markets(_target);
    }

    function deployAdapter(address _target) external override returns (address adapter) {
        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a CAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        adapter = address(
            new CAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                factoryParams.oracle,
                factoryParams.ifee,
                factoryParams.stake,
                factoryParams.stakeSize,
                factoryParams.minm,
                factoryParams.maxm,
                factoryParams.mode,
                factoryParams.tilt,
                DEFAULT_LEVEL,
                reward
            )
        );

        _addAdapter(adapter);
    }
}
