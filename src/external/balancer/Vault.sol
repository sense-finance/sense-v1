// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

interface IAsset { }

interface Vault {
    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }
    enum SwapKind { GIVEN_IN, GIVEN_OUT }
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function getPoolTokens(bytes32 poolId) external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256 maxBlockNumber
    );
}