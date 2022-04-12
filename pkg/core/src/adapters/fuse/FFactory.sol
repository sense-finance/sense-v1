// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { CropFactory } from "../CropFactory.sol";
import { FAdapter, ComptrollerLike, RewardsDistributorLike } from "./FAdapter.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

// External references
import { Bytes32AddressLib } from "@rari-capital/solmate/src/utils/Bytes32AddressLib.sol";

interface FTokenLike {
    function underlying() external view returns (address);
}

interface FusePoolLensLike {
    function poolExists(address comptroller) external view returns (bool);
}

contract FFactory is CropFactory {
    using Bytes32AddressLib for address;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant FUSE_POOL_DIRECTORY = 0x835482FE0532f169024d5E9410199369aAD5C77E;

    constructor(address _divider, FactoryParams memory _factoryParams) CropFactory(_divider, _factoryParams) {}

    function deployAdapter(address _target, address _comptroller) external override returns (address adapter) {
        /// Sanity checks
        /// TODO: any better way to verify this?
        if (!FusePoolLensLike(FUSE_POOL_DIRECTORY).poolExists(_comptroller)) revert Errors.InvalidParam();
        (bool isListed, ) = ComptrollerLike(_comptroller).markets(_target);
        if (!isListed) revert Errors.TargetNotSupported();

        address[] memory rewardTokens = new address[](10); // TODO: we will support max 10 reward tokens. Orr any other idea?
        address underlying = FTokenLike(_target).underlying();

        // get current reward tokens for given _target and _comptroller
        address[] memory rewardsDistributors = ComptrollerLike(_comptroller).getRewardsDistributors();
        for (uint256 i = 0; i < rewardsDistributors.length; i++) {
            (, uint32 lastUpdatedTimestamp) = RewardsDistributorLike(rewardsDistributors[i]).marketState(_target);
            if (lastUpdatedTimestamp > 0)
                rewardTokens[i] = RewardsDistributorLike(rewardsDistributors[i]).rewardToken();
        }

        // TODO: check _comptroller is valid
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: _target,
            underlying: underlying == address(0) ? WETH : underlying, // TODO: are we good witht this check right?
            oracle: factoryParams.oracle,
            stake: factoryParams.stake,
            stakeSize: factoryParams.stakeSize,
            minm: factoryParams.minm,
            maxm: factoryParams.maxm,
            mode: factoryParams.mode,
            ifee: factoryParams.ifee,
            tilt: factoryParams.tilt,
            level: DEFAULT_LEVEL
        });
        // Use the CREATE2 opcode to deploy a new Adapter contract.
        // This will revert if a CAdapter with the provided target has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        adapter = address(
            new FAdapter{ salt: _target.fillLast12Bytes() }(divider, _comptroller, adapterParams, rewardTokens)
        );
    }
}
