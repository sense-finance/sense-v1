// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { CropAdapter } from "./CropAdapter.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { BaseFactory } from "./BaseFactory.sol";

abstract contract CropFactory is BaseFactory {
    address public immutable reward;

    constructor(
        address _divider,
        address _protocol,
        FactoryParams memory _factoryParams,
        address _reward
    ) BaseFactory(_divider, _protocol, _factoryParams) {
        reward = _reward;
    }
}
