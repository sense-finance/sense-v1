// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Internal references
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { Divider } from "../../../Divider.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Trust } from "@sense-finance/v1-utils/Trust.sol";

interface ERC20 {
    function decimals() external view returns (uint256 decimals);
}

interface ChainlinkOracleLike {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint256 decimals);
}

abstract contract BaseFactory is Trust {
    using FixedMath for uint256;

    /* ========== CONSTANTS ========== */

    address public constant ETH_USD_PRICEFEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH-USD price feed

    /// @notice Sets level to `31` by default, which keeps all Divider lifecycle methods public
    /// (`issue`, `combine`, `collect`, etc), but not the `onRedeem` hook.
    uint48 public constant DEFAULT_LEVEL = 31;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    address public immutable divider;

    /// @notice Adapter admin address
    address public restrictedAdmin;

    /// @notice Rewards recipient
    address public rewardsRecipient;

    /// @notice params for adapters deployed with this factory
    FactoryParams public factoryParams;

    /* ========== DATA STRUCTURES ========== */

    struct FactoryParams {
        address oracle; // oracle address
        address stake; // token to stake at issuance
        uint256 stakeSize; // amount to stake at issuance
        uint256 minm; // min maturity (seconds after block.timstamp)
        uint256 maxm; // max maturity (seconds after block.timstamp)
        uint128 ifee; // issuance fee
        uint16 mode; // 0 for monthly, 1 for weekly
        uint64 tilt; // tilt
        uint256 guard; // adapter guard (in usd, 18 decimals)
    }

    constructor(
        address _divider,
        address _restrictedAdmin,
        address _rewardsRecipient,
        FactoryParams memory _factoryParams
    ) Trust(msg.sender) {
        divider = _divider;
        restrictedAdmin = _restrictedAdmin;
        rewardsRecipient = _rewardsRecipient;
        factoryParams = _factoryParams;
    }

    /* ========== REQUIRED DEPLOY ========== */

    /// @notice Deploys both an adapter and a target wrapper for the given _target
    /// @param _target Address of the Target token
    /// @param _data Additional data needed to deploy the adapter
    function deployAdapter(address _target, bytes memory _data) external virtual returns (address adapter) {}

    /// Set adapter's guard to $100`000 in target
    /// @notice if Underlying-ETH price feed returns 0, we set the guard to 100000 target.
    function _setGuard(address _adapter) internal {
        // We only want to execute this if divider is guarded
        if (Divider(divider).guarded()) {
            BaseAdapter adapter = BaseAdapter(_adapter);

            // Get Underlying-ETH price (18 decimals)
            try adapter.getUnderlyingPrice() returns (uint256 underlyingPriceInEth) {
                // Get ETH-USD price from Chainlink (8 decimals)
                (, int256 ethPrice, , uint256 ethUpdatedAt, ) = ChainlinkOracleLike(ETH_USD_PRICEFEED)
                    .latestRoundData();

                if (block.timestamp - ethUpdatedAt > 2 hours) revert Errors.InvalidPrice();

                // Calculate Underlying-USD price (normalised to 18 deicmals)
                uint256 price = underlyingPriceInEth.fmul(uint256(ethPrice), 1e8);

                // Calculate Target-USD price (scale and price are in 18 decimals)
                price = adapter.scale().fmul(price);

                // Calculate guard with factory guard (18 decimals) and target price (18 decimals)
                // normalised to target decimals and set it
                Divider(divider).setGuard(
                    _adapter,
                    factoryParams.guard.fdiv(price, 10**ERC20(adapter.target()).decimals())
                );
            } catch {}
        }
    }

    function setRestrictedAdmin(address _restrictedAdmin) external requiresTrust {
        emit RestrictedAdminChanged(restrictedAdmin, _restrictedAdmin);
        restrictedAdmin = _restrictedAdmin;
    }

    /// Set factory rewards recipient
    /// @notice all future deployed adapters will have the new rewards recipient
    /// @dev existing adapters rewards recipients will not be changed and can be
    /// done through `setRewardsRecipient` on each adapter contract
    function setRewardsRecipient(address _recipient) external requiresTrust {
        emit RewardsRecipientChanged(rewardsRecipient, _recipient);
        rewardsRecipient = _recipient;
    }

    /// @notice sets trusted address for an adapter
    /// @dev factory must already be a trusted address for the adapter
    function setAdapterTrusted(
        address _adapter,
        address _user,
        bool _trusted
    ) public requiresTrust {
        Trust(_adapter).setIsTrusted(_user, _trusted);
    }

    /// Set factory params
    /// @dev existing adapters will not be affected
    function setFactoryParams(FactoryParams calldata _factoryParams) external requiresTrust {
        emit FactoryParamsChanged(_factoryParams);
        factoryParams = _factoryParams;
    }

    /* ========== LOGS ========== */

    event RewardsRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event RestrictedAdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event FactoryParamsChanged(FactoryParams factoryParams);
}
