// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";

contract MockUniV3Pool {
    function initialize(uint160 sqrtPriceX96) external {}

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](2);
        secondsPerLiquidityCumulativeX128s = new uint160[](2);
        tickCumulatives[0] = type(int56).max;
        tickCumulatives[1] = type(int56).max;
        secondsPerLiquidityCumulativeX128s[0] = type(uint160).max;
        secondsPerLiquidityCumulativeX128s[1] = type(uint160).max;
    }
}

contract MockUniFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool) {
        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        require(getPool[token0][token1][fee] == address(0));
        pool = address(new MockUniV3Pool());
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
    }
}
