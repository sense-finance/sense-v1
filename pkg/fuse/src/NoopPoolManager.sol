// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Pool manager implementation with no restrictions where every function is a no-op. Refer to "PoolManager.sol" for
// the normal behavior of a Pool Manager.
contract NoopPoolManager {
    function deployPool(
        string calldata name,
        uint256 closeFactor,
        uint256 liqIncentive,
        address fallbackOracle
    ) external returns (uint256 _poolIndex, address _comptroller) {
        emit PoolDeployed(name, _comptroller, _poolIndex, closeFactor, liqIncentive);
    }

    function addTarget(address target, address adapter) external returns (address cTarget) {
        emit TargetAdded(target, cTarget);
    }

    function queueSeries(
        address adapter,
        uint256 maturity,
        address pool
    ) external {
        emit SeriesQueued(adapter, maturity, pool);
    }

    function addSeries(address adapter, uint256 maturity) external returns (address, address) {}

    event PoolDeployed(string name, address comptroller, uint256 poolIndex, uint256 closeFactor, uint256 liqIncentive);
    event TargetAdded(address indexed target, address indexed cTarget);
    event SeriesQueued(address indexed adapter, uint256 indexed maturity, address indexed pool);
}
