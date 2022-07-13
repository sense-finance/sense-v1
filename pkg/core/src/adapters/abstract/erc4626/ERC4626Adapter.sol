// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
// import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

// Internal references
import { IPriceFeed } from "../../implementations/oracles/IPriceFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { BaseAdapter } from "../BaseAdapter.sol";

interface ChainlinkOracleLike {
    /// @notice get data about the latest round. Consumers are encouraged to check
    /// that they're receiving fresh data by inspecting the updatedAt and
    /// answeredInRound return values.
    /// Note that different underlying implementations of AggregatorV3Interface
    /// have slightly different semantics for some of the return values. Consumers
    /// should determine what implementations they expect to receive
    /// data from and validate that they can properly handle return data from all
    /// of them.
    /// @param base base asset address
    /// @param quote quote asset address
    /// @return roundId is the round ID from the aggregator for which the data was
    /// retrieved combined with a phase to ensure that round IDs get larger as
    /// time moves forward.
    /// @return answer is the answer for the given round
    /// @return startedAt is the timestamp when the round was started.
    /// (Only some AggregatorV3Interface implementations return meaningful values)
    /// @return updatedAt is the timestamp when the round last was updated (i.e.
    /// answer was last computed)
    /// @return answeredInRound is the round ID of the round in which the answer
    /// was computed.
    /// (Only some AggregatorV3Interface implementations return meaningful values)
    /// @dev Note that answer and updatedAt may change between queries.
    function latestRoundData(address base, address quote)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @dev This interface is from Chainlink's direct oracles (non-registry)
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
}

/// @notice Adapter contract for ERC4626 Vaults
contract ERC4626Adapter is
    BaseAdapter // TODO:, Trust {
{
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    address public constant CHAINLINK_REGISTRY = 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf; // Chainlink Registry
    address public constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH-USD price feed

    uint256 public immutable BASE_UINT;
    uint256 public immutable SCALE_FACTOR;

    constructor(
        address _divider,
        address _target,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, address(ERC4626(_target).asset()), _ifee, _adapterParams) {
        // TODO: Trust(msg.sender) {
        uint256 tDecimals = ERC4626(target).decimals();
        BASE_UINT = 10**tDecimals;
        SCALE_FACTOR = 10**(18 - tDecimals); // we assume targets decimals <= 18
        ERC20(underlying).approve(target, type(uint256).max);
    }

    function scale() external override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function scaleStored() external view override returns (uint256) {
        return ERC4626(target).convertToAssets(BASE_UINT) * SCALE_FACTOR;
    }

    function getUnderlyingPrice() external view override returns (uint256 price) {
        // We try getting the UNDERLYING-ETH price from Chainlink's registry
        address ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        try ChainlinkOracleLike(CHAINLINK_REGISTRY).latestRoundData(underlying, ETH) returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (block.timestamp - updatedAt > 1 hours) revert Errors.InvalidPrice();
            price = uint256(answer);
        } catch {
            // If not found, we try getting the UNDERLYING-USD price from Chainlink's registry
            address USD = 0x0000000000000000000000000000000000000348;
            try ChainlinkOracleLike(CHAINLINK_REGISTRY).latestRoundData(underlying, USD) returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) {
                // If found, we now have to get the ETH-USD price from Chainlink's ETH-USD price feed
                // so we can then calculate he UNDERLYING-ETH price

                // Get ETH-USD price directly from oracle (no registry)
                (, int256 ethPrice, , uint256 ethUpdatedAt, ) = ChainlinkOracleLike(CHAINLINK_ETH_USD)
                    .latestRoundData();

                // Sanity checks
                if (block.timestamp - updatedAt > 1 hours) revert Errors.InvalidPrice();
                if (block.timestamp - ethUpdatedAt > 1 hours) revert Errors.InvalidPrice();

                // Calculate Underlying-ETH price
                price = uint256(answer).fdiv(uint256(ethPrice));
            } catch {
                // If not found, we check if there's a custom oracle or revert otherwise
                if (adapterParams.oracle == address(0)) revert Errors.PriceNotFound();
                (price, ) = IPriceFeed(adapterParams.oracle).price();
            }
        }

        if (price < 0) revert Errors.InvalidPrice();
    }

    function wrapUnderlying(uint256 assets) external override returns (uint256 _shares) {
        ERC20(underlying).safeTransferFrom(msg.sender, address(this), assets);
        _shares = ERC4626(target).deposit(assets, msg.sender);
    }

    function unwrapTarget(uint256 shares) external override returns (uint256 _assets) {
        _assets = ERC4626(target).redeem(shares, msg.sender, msg.sender);
    }

    /// @notice set a cusom oracle for this adapter
    /// @param _oracle address of the oracle to use
    /// @dev The oracle passed must comply with the IPriceFeed interface
    function setOracle(address _oracle) external {
        // TODO: requiresTrust {
        adapterParams.oracle = _oracle;
        emit OracleUpdated(_oracle);
    }

    event OracleUpdated(address indexed oracle);
}
