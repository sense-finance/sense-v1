// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IAdapter {
    function divider() external view virtual returns (address divider);

    function target() external view virtual returns (address target);

    function oracle() external view virtual returns (address oracle);

    function name() external view virtual returns (string memory name);

    function symbol() external view virtual returns (string memory symbol);

    function delta() external view virtual returns (uint256 delta);

    function scale() external virtual returns (uint256 _scale);

    function stake() external virtual returns (address _stake);

    function ifee() external virtual returns (uint256 _issuanceFee);

    function stakeSize() external virtual returns (uint256 _stakeSize);

    function minm() external virtual returns (uint256 _minMaturity);

    function maxm() external virtual returns (uint256 _maxMaturity);

    function mode() external virtual returns (uint8 _mode);

    function initialize(
        address _target,
        address _divider,
        uint256 _delta
    ) external virtual;
}
