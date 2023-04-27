// SPDX-License-Identifier: GNU AGPLv3
pragma solidity ^0.8.0;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Sense Multi Rewards Distributor.
/// @author Sense Finance.
/// @notice This contract allows users to claim their rewards. This contract is largely inspired by Morpho's Reward Distributor contract: https://github.com/morpho-dao/morpho-v1/blob/main/src/common/rewards-distribution/RewardsDistributor.sol.
/// and modified to allow multiple rewards tokens.
contract MultiRewardsDistributor is Ownable {
    using SafeTransferLib for ERC20;

    /// STORAGE ///

    struct Node {
        bytes32 currRoot; // The merkle tree's root of the current rewards distribution.
        bytes32 prevRoot; // The merkle tree's root of the previous rewards distribution.
        mapping(address => uint256) claimed; // The rewards already claimed. account -> amount.
    }
    mapping(ERC20 => Node) public nodes;

    ERC20[] public rewards;

    /// EVENTS ///

    /// @notice Emitted when the root is updated.
    /// @param newRoot The new merkle's tree root.
    event RootUpdated(ERC20 reward, bytes32 newRoot);

    /// @notice Emitted when reward tokens are withdrawn.
    /// @param reward The address of the reward token.
    /// @param to The address of the recipient.
    /// @param amount The amount of reward tokens withdrawn.
    event RewardsWithdrawn(ERC20 reward, address to, uint256 amount);

    /// @notice Emitted when an account claims rewards.
    /// @param reward The address of the reward token.
    /// @param account The address of the claimer.
    /// @param amount The amount of rewards claimed.
    event RewardsClaimed(ERC20 reward, address account, uint256 amount);

    /// ERRORS ///

    /// @notice Thrown when the proof is invalid or expired.
    error ProofInvalidOrExpired();

    /// @notice Thrown when the claimer has already claimed the rewards.
    error AlreadyClaimed();

    /// CONSTRUCTOR ///

    /// @notice Constructs Morpho's RewardsDistributor contract.
    /// @param _rewards The address of the MORPHO token to distribute.
    constructor(ERC20[] memory _rewards) {
        rewards = _rewards;
    }

    /// EXTERNAL ///

    /// @notice Updates the current merkle tree's root.
    /// @param _newRoot The new merkle tree's root.
    function updateRoot(ERC20 _reward, bytes32 _newRoot) external onlyOwner {
        nodes[_reward].prevRoot = nodes[_reward].currRoot;
        nodes[_reward].currRoot = _newRoot;
        emit RootUpdated(_reward, _newRoot);
    }

    /// @notice Withdraws reward tokens to a recipient.
    /// @param _to The address of the recipient.
    /// @param _amounts The amounts for each reward token to transfer.
    function withdrawTokens(address _to, uint256[] calldata _amounts) external onlyOwner {
        for (uint256 i = 0; i < rewards.length; i++) {
            ERC20 reward = rewards[i];
            uint256 rewardBalance = reward.balanceOf(address(this));
            uint256 toWithdraw = rewardBalance < _amounts[i] ? rewardBalance : _amounts[i];
            reward.safeTransfer(_to, toWithdraw);
            emit RewardsWithdrawn(reward, _to, toWithdraw);
        }
    }

    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _claimable The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function claim(
        ERC20 _reward,
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external {
        bytes32 candidateRoot = MerkleProof.processProof(
            _proof,
            keccak256(abi.encodePacked(_reward, _account, _claimable))
        );
        if (candidateRoot != nodes[_reward].currRoot && candidateRoot != nodes[_reward].prevRoot)
            revert ProofInvalidOrExpired();

        uint256 alreadyClaimed = nodes[_reward].claimed[_account];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        nodes[_reward].claimed[_account] = _claimable;

        _reward.safeTransfer(_account, amount);
        emit RewardsClaimed(_reward, _account, amount);
    }
}
