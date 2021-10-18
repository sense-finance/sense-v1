// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

/// Taken from https://github.com/xtokenmarket/xalpha/blob/main/contracts/mock/MockUniswapV3Router.sol
contract MockUniSwapRouter {

    uint256 public constant EXCHANGE_RATE = 100;

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256) {
        uint256 exchangeRate = 100;
        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        uint256 amountOut = params.amountIn / exchangeRate;
        require(amountOut >= params.amountOutMinimum, "amountOutMin invariant failed");

        ERC20(params.tokenOut).transfer(params.recipient, amountOut);
        return amountOut;
    }

    receive() external payable {}
}