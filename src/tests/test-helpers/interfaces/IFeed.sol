// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IFeed {
    function divider() external view virtual returns (address divider);

    function target() external view virtual returns (address target);

    function name() external view virtual returns (string memory name);

    function symbol() external view virtual returns (string memory symbol);

    function delta() external view virtual returns (uint256 delta);

    function scale() external virtual returns (uint256 _scale);

    function initialise(
        address _target,
        address _divider,
        uint256 _delta
    ) external virtual;
}
