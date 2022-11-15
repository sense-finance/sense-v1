// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

contract MockPoolManager {
    mapping(address => bool) public tInits; // Target Inits: target -> target added to pool
    mapping(address => mapping(uint256 => bool)) public sInits;

    //     Series Inits: adapter -> maturity -> series (principalyields) added to pool

    function deployPool(
        string calldata name,
        bool whitelist,
        uint256 closeFactor,
        uint256 liqIncentive
    ) external returns (uint256 _poolIndex, address _comptroller) {
        return (0, address(1));
    }

    function addTarget(address target) external {
        tInits[target] = true;
    }

    function addSeries(address adapter, uint256 maturity) external {
        sInits[adapter][maturity] = true;
    }
}
