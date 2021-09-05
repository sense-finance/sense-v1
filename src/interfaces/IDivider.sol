pragma solidity ^0.8.6;

abstract contract IDivider {
    function initSeries(address feed, uint256 maturity) external virtual returns (address zero, address claim);

    function settleSeries(address feed, uint256 maturity) external virtual;

    function issue(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function combine(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function redeemZero(
        address feed,
        uint256 maturity,
        uint256 balance
    ) external virtual;

    function collect(
        address usr,
        address feed,
        uint256 maturity,
        uint256 balance
    ) external virtual returns (uint256 _collected);

    function setFeed(address feed, bool isOn) external virtual;

    function backfillScale(
        address feed,
        uint256 maturity,
        uint256 scale
    ) external virtual;

    function stop() external virtual;

    function setStableAsset(address _stableAsset) external virtual;
}
