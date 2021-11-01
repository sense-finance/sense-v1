// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

abstract contract IDivider {
    function series(address adapter, uint256 maturity)
        external
        virtual
        returns (
            address,
            address,
            uint256,
            address
        );

    function initSeries(address adapter, uint256 maturity) external virtual returns (address zero, address claim);

    function settleSeries(address adapter, uint256 maturity) external virtual;

    function issue(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function combine(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function redeemZero(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function collect(
        address usr,
        address adapter,
        uint256 maturity,
        uint256 balance
    ) external virtual returns (uint256 _collected);

    function setAdapter(address adapter, bool isOn) external virtual;

    function backfillScale(
        address adapter,
        uint256 maturity,
        uint256 scale,
        bytes[] memory backfills
    ) external virtual;
}
