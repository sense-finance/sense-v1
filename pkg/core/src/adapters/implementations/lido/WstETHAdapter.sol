// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { FixedMath } from "../../../external/FixedMath.sol";

// Internal references
import { BaseAdapter } from "../../abstract/BaseAdapter.sol";
import { ExtractableReward } from "../../abstract/extensions/ExtractableReward.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

interface WstETHLike {
    /// @notice Exchanges wstETH to stETH
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    /// @notice Exchanges stETH to wstETH
    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface StETHLike {
    /// @notice Get amount of stETH for a one wstETH
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}

interface PriceOracleLike {
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

/// @notice Adapter contract for wstETH
contract WstETHAdapter is BaseAdapter, ExtractableReward {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant STETH_USD_PRICEFEED = 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8; // Chainlink stETH-USD price feed
    address public constant ETH_USD_PRICEFEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH-USD price feed

    /// @notice Cached scale value from the last call to `scale()`
    uint256 public override scaleStored;

    constructor(
        address _divider,
        address _target,
        address _rewardsRecipient,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, STETH, _ifee, _adapterParams) ExtractableReward(_rewardsRecipient) {
        // approve wstETH contract to pull stETH (used on wrapUnderlying())
        ERC20(STETH).approve(WSTETH, type(uint256).max);
        // set an inital cached scale value
        scaleStored = StETHLike(STETH).getPooledEthByShares(1 ether);
    }

    /// @return exRate Eth per wstEtH (natively in 18 decimals)
    function scale() external virtual override returns (uint256 exRate) {
        exRate = StETHLike(STETH).getPooledEthByShares(1 ether);

        if (exRate != scaleStored) {
            // update value only if different than the previous
            scaleStored = exRate;
        }
    }

    /// @dev To calculate stETH-ETH price we use Chainlink's stETH-USD and ETH-USD price feeds.
    function getUnderlyingPrice() external view override returns (uint256 price) {
        (, int256 stethPrice, , uint256 stethUpdatedAt, ) = PriceOracleLike(STETH_USD_PRICEFEED).latestRoundData();
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = PriceOracleLike(ETH_USD_PRICEFEED).latestRoundData();
        if (block.timestamp - stethUpdatedAt > 2 hours) revert Errors.InvalidPrice();
        if (block.timestamp - ethUpdatedAt > 2 hours) revert Errors.InvalidPrice();
        price = uint256(stethPrice).fdiv(uint256(ethPrice));
        if (price < 0) revert Errors.InvalidPrice();
    }

    function unwrapTarget(uint256 amount) external override returns (uint256 stETH) {
        ERC20(WSTETH).safeTransferFrom(msg.sender, address(this), amount); // pull wstETH
        // unwrap wstETH into stETH and transfer it back to sender
        ERC20(STETH).safeTransfer(msg.sender, stETH = WstETHLike(WSTETH).unwrap(amount));
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256 wstETH) {
        ERC20(STETH).safeTransferFrom(msg.sender, address(this), amount); // pull STETH
        // wrap stETH into wstETH and transfer it back to sender
        ERC20(WSTETH).safeTransfer(msg.sender, wstETH = WstETHLike(WSTETH).wrap(amount));
    }

    function _isValid(address _token) internal override returns (bool) {
        return (_token != target && _token != adapterParams.stake);
    }
}
