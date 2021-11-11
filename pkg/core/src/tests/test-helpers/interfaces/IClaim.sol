// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IClaim {
    function collect() external virtual returns (uint256 _collected);
}