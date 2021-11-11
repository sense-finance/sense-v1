// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IAdapter {
    function divider() external view virtual returns (address divider);

    function target() external view virtual returns (address target);

    function name() external view virtual returns (string memory name);

    function symbol() external view virtual returns (string memory symbol);

    function delta() external view virtual returns (uint256 delta);

    function scale() external virtual returns (uint256 _scale);

    function stake() external virtual returns (address _stake);

    function issuanceFee() external virtual returns (uint256 _issuanceFee);

    function stakeSize() external virtual returns (uint256 _stakeSize);

    function minMaturity() external virtual returns (uint256 _minMaturity);

    function maxMaturity() external virtual returns (uint256 _maxMaturity);

    function initialize(
        address _target,
        address _divider,
        uint256 _delta
    ) external virtual;
}
