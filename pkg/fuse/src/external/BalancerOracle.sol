// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

interface BalancerOracle {
    function getTimeWeightedAverage(OracleAverageQuery[] memory queries)
        external
        view
        returns (uint256[] memory results);

    enum Variable {
        PAIR_PRICE,
        BPT_PRICE,
        INVARIANT
    }
    struct OracleAverageQuery {
        Variable variable;
        uint256 secs;
        uint256 ago;
    }

    function getSample(uint256 index)
        external
        view
        returns (
            int256 logPairPrice,
            int256 accLogPairPrice,
            int256 logBptPrice,
            int256 accLogBptPrice,
            int256 logInvariant,
            int256 accLogInvariant,
            uint256 timestamp
        );

    function getPoolId() external view returns (bytes32);

    function getVault() external view returns (address);

    function getIndices() external view returns (uint256 _pti, uint256 _targeti);

    function totalSupply() external view returns (uint256);

    function getTotalSamples() external pure returns (uint256);
}
