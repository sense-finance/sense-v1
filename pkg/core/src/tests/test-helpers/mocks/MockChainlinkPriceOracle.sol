// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ChainlinkPriceOracle, FeedRegistryLike } from "../../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";

/// @notice we need these mocks since Foundry does not yet support mocking reverts
contract MockChainlinkPriceOracle is ChainlinkPriceOracle {
    constructor(FeedRegistryLike _feedRegistry) ChainlinkPriceOracle(0) {
        feedRegistry = _feedRegistry;
    }
}

contract MockFeedRegistry is FeedRegistryLike {
    mapping(address => mapping(address => string)) public revertMessages;

    function latestRoundData(address base, address quote)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (keccak256(abi.encodePacked(revertMessages[base][quote])) != keccak256(abi.encodePacked(""))) {
            revert(revertMessages[base][quote]);
        } else {
            return (uint80(0), int256(0), uint256(0), uint256(0), uint80(0));
        }
    }

    function decimals(address base, address quote) external view returns (uint8) {
        return 0;
    }

    function setRevert(
        address base,
        address quote,
        string memory _revertMsg
    ) public {
        revertMessages[base][quote] = _revertMsg;
    }
}
