// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Assets } from "./Assets.sol";

// Uniswap
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface WstETHInterface {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface StETHInterface {
    function submit(address _referral) external payable returns (uint256);
}

interface CTokenInterface {
    function mint(uint mintAmount) external returns (uint);
}


contract LiquidityHelper {
    using SafeERC20 for ERC20;

    uint24 public constant UNI_POOL_FEE = 3000; // denominated in hundredths of a bip

    function addLiquidity(address[] memory assets) public {
        address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        for (uint256 i = 0; i < assets.length; i++) {
            swap(DAI, assets[i], 1000e18, address(this));
        }
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, address recipient) public returns (uint256) {
        uint256 amountOut = 0;
        if (tokenOut == Assets.WSTETH) {
            uint256 stETH = StETHInterface(Assets.STETH).submit{value: 10 ether}(address(0));
            ERC20(Assets.STETH).safeApprove(Assets.WSTETH, stETH);
            amountOut = WstETHInterface(Assets.WSTETH).wrap(stETH);
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountOut;
        }
        if (tokenOut == Assets.cDAI) {
            ERC20(Assets.DAI).safeApprove(Assets.cDAI, amountIn);
            amountOut = CTokenInterface(Assets.cDAI).mint(amountIn);
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountOut;
        }
        
        // approve router to spend tokenIn
        ERC20(tokenIn).safeApprove(Assets.UNISWAP_ROUTER, amountIn);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: UNI_POOL_FEE,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0 // set to be 0 to ensure we swap our exact input amount
        });
        amountOut = ISwapRouter(Assets.UNISWAP_ROUTER).exactInputSingle(params); // executes the swap
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }

    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

}
