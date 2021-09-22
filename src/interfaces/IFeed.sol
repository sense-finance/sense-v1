// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IFeed {
    function divider() external view virtual returns (address divider);

    function target() external view virtual returns (address target);

    function name() external view virtual returns (string memory name);

    function symbol() external view virtual returns (string memory symbol);

    function scale() external virtual returns (uint256 _scale);
}
