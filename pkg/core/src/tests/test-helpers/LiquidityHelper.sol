// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { Hevm } from "./Hevm.sol";

// Internal references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Assets } from "./Assets.sol";

interface SwapRouterLike {
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

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface WstETHInterface {
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function wrap(uint256 _stETHAmount) external returns (uint256);
}

interface StETHInterface {
    function submit(address _referral) external payable returns (uint256);
}

interface CTokenInterface {
    function mint(uint256 mintAmount) external returns (uint256);
}

interface CETHTokenInterface {
    ///@notice Send Ether to CEther to mint
    function mint() external payable;
}

contract LiquidityHelper {
    using SafeTransferLib for ERC20;

    uint24 public constant UNI_POOL_FEE = 3000; // denominated in hundredths of a bip

    function giveTokens(
        address token,
        uint256 amount,
        Hevm hevm
    ) internal returns (bool) {
        // Edge case - balance is already set for some reason
        if (ERC20(token).balanceOf(address(this)) == amount) return true;

        for (int256 i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(address(token), keccak256(abi.encode(address(this), uint256(i))));
            hevm.store(address(token), keccak256(abi.encode(address(this), uint256(i))), bytes32(amount));
            if (ERC20(token).balanceOf(address(this)) == amount) {
                // Found it
                return true;
            } else {
                // Keep going after restoring the original value
                hevm.store(address(token), keccak256(abi.encode(address(this), uint256(i))), prevValue);
            }
        }

        // We have failed if we reach here
        return false;
    }

    function addLiquidity(address[] memory assets) public {
        uint256 amountIn = 10 ether;
        for (uint256 i = 0; i < assets.length; i++) {
            Assets.WETH.call{ value: amountIn }("");
            swap(Assets.WETH, assets[i], amountIn, address(this));
        }
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) public returns (uint256) {
        uint256 amountOut = 0;
        if (tokenOut == Assets.WSTETH) {
            uint256 stETH = StETHInterface(Assets.STETH).submit{ value: amountIn }(address(0));
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
        if (tokenOut == Assets.cETH) {
            Assets.cETH.call{ value: amountIn }("");
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountIn;
        }
        if (tokenOut == Assets.WETH) {
            return amountIn;
        }

        // approve router to spend tokenIn
        ERC20(tokenIn).safeApprove(Assets.UNISWAP_ROUTER, amountIn);
        SwapRouterLike.ExactInputSingleParams memory params = SwapRouterLike.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: UNI_POOL_FEE,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0 // set to be 0 to ensure we swap our exact input amount
        });
        amountOut = SwapRouterLike(Assets.UNISWAP_ROUTER).exactInputSingle(params); // executes the swap
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }

    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
}
