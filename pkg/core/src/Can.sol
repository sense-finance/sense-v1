// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Toke } from "./Deployer.sol";

contract Wrap {
    function wrap(
        address divider,
        address adapter,
        uint48 maturity
    ) public returns (address, address) {
        return Toke.create(divider, adapter, maturity);
    }
}
