// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

abstract contract IDivider {
    function series(address adapter, uint48 maturity)
        external
        virtual
        returns (
            address,
            address,
            uint256,
            address
        );

    function initSeries(address adapter, uint48 maturity) external virtual returns (address zero, address claim);

    function settleSeries(address adapter, uint48 maturity) external virtual;

    function issue(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) external virtual;

    function combine(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) external virtual;

    function redeemZero(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) external virtual;

    function collect(
        address usr,
        address adapter,
        uint48 maturity,
        uint256 balance
    ) external virtual returns (uint256 _collected);

    function setAdapter(address adapter, bool isOn) external virtual;

    function backfillScale(
        address adapter,
        uint48 maturity,
        uint256 scale,
        bytes[] memory backfills
    ) external virtual;
}
