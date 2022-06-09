// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { CropsFactory } from "../../abstract/factories/CropsFactory.sol";
import { FAdapter, FComptrollerLike, RewardsDistributorLike } from "./FAdapter.sol";
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

interface FTokenLike {
    function underlying() external view returns (address);

    function isCEther() external view returns (bool);
}

interface FusePoolLensLike {
    function poolExists(address comptroller) external view returns (bool);
}

contract FFactory is CropsFactory {
    using Bytes32AddressLib for address;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant FUSE_POOL_DIRECTORY = 0x835482FE0532f169024d5E9410199369aAD5C77E;

    constructor(address _divider, FactoryParams memory _factoryParams) CropsFactory(_divider, _factoryParams) {}

    function deployAdapter(address _target, bytes memory data) external override returns (address adapter) {
        address comptroller = abi.decode(data, (address));

        /// Sanity checks
        if (!FusePoolLensLike(FUSE_POOL_DIRECTORY).poolExists(comptroller)) revert Errors.InvalidParam();
        (bool isListed, ) = FComptrollerLike(comptroller).markets(_target);
        if (!isListed) revert Errors.TargetNotSupported();

        // Initialize rewardTokens by calling getRewardsDistributors() -> rewardToken()
        address[] memory rewardsDistributors = FComptrollerLike(comptroller).getRewardsDistributors();
        address[] memory rewardTokens = new address[](rewardsDistributors.length);
        address[] memory targetRewardsDistributors = new address[](rewardsDistributors.length);

        uint256 idx;
        for (uint256 i = 0; i < rewardsDistributors.length; i++) {
            (, uint32 lastUpdatedTimestamp) = RewardsDistributorLike(rewardsDistributors[i]).marketState(_target);
            if (lastUpdatedTimestamp > 0) {
                rewardTokens[idx] = RewardsDistributorLike(rewardsDistributors[i]).rewardToken();
                targetRewardsDistributors[idx] = rewardsDistributors[i];
                idx = idx + 1;
            }
        }

        address underlying = FTokenLike(_target).underlying();
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });
        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a FAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        adapter = address(
            new FAdapter{ salt: _target.fillLast12Bytes() }(
                divider,
                _target,
                FTokenLike(_target).isCEther() ? WETH : underlying,
                factoryParams.ifee,
                comptroller,
                adapterParams,
                rewardTokens,
                targetRewardsDistributors
            )
        );
    }

    /// @notice Replace existing rewards tokens and distributorsfor a given adapter
    /// @param _adapter address of adapter to update
    /// @param _rewardTokens array of rewards tokens addresses
    /// @param _adapter array of adapters to update the rewards tokens on
    function setRewardTokens(
        address _adapter,
        address[] memory _rewardTokens,
        address[] memory _rewardsDistributors
    ) public virtual requiresTrust {
        FAdapter(payable(_adapter)).setRewardTokens(_rewardTokens, _rewardsDistributors);
    }
}
