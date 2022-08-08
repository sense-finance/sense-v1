// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { Hevm } from "./Hevm.sol";

// Internal references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { AddressBook } from "./AddressBook.sol";

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

interface WETHInterface {
    function withdraw(uint256 wad) external;
}

contract LiquidityHelper {
    using SafeTransferLib for ERC20;

    mapping(address => int256) public slots;

    constructor() {
        slots[AddressBook.RSTETH_THETA] = 151;
    }

    uint24 public constant UNI_POOL_FEE = 3000; // denominated in hundredths of a bip

    function giveTokens(
        address token,
        address to,
        uint256 amount,
        Hevm hevm
    ) internal returns (bool) {
        return _giveTokens(token, to, amount, hevm);
    }

    function giveTokens(
        address token,
        uint256 amount,
        Hevm hevm
    ) internal returns (bool) {
        return _giveTokens(token, address(this), amount, hevm);
    }

    function _giveTokens(
        address token,
        address to,
        uint256 amount,
        Hevm hevm
    ) internal returns (bool) {
        // Edge case - balance is already set for some reason
        if (ERC20(token).balanceOf(to) == amount) return true;

        bool isStETH = token == AddressBook.STETH;
        if (isStETH) {
            token = AddressBook.WETH;
        }

        for (int256 slot = 0; slot < 9500; slot++) {
            // Scan the storage for the balance storage slot
            // If we slot is alrerady in the mapping, we don't scan
            if (slots[token] != 0) slot = slots[token];
            bytes32 prevValue = hevm.load(address(token), keccak256(abi.encode(to, uint256(slot))));
            hevm.store(address(token), keccak256(abi.encode(to, uint256(slot))), bytes32(amount));
            if (ERC20(token).balanceOf(to) == amount) {
                // Found it
                if (isStETH) {
                    // ERC20(AddressBook.WETH).approve(AddressBook.WETH, type(uint256).max);
                    hevm.startPrank(to);
                    WETHInterface(token).withdraw(amount); // unwrap WETH into ETH
                    StETHInterface(AddressBook.STETH).submit{ value: amount }(address(0)); // stake ETH (returns stETH)
                    hevm.stopPrank();
                }
                return true;
            } else {
                // Keep going after restoring the original value
                hevm.store(address(token), keccak256(abi.encode(to, uint256(slot))), prevValue);
            }
        }

        // We have failed if we reach here
        return false;
    }

    function addLiquidity(address[] memory assets) public {
        uint256 amountIn = 10 ether;
        for (uint256 i = 0; i < assets.length; i++) {
            AddressBook.WETH.call{ value: amountIn }("");
            swap(AddressBook.WETH, assets[i], amountIn, address(this));
        }
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient
    ) public returns (uint256) {
        uint256 amountOut = 0;
        if (tokenOut == AddressBook.WSTETH) {
            uint256 stETH = StETHInterface(AddressBook.STETH).submit{ value: amountIn }(address(0));
            ERC20(AddressBook.STETH).approve(AddressBook.WSTETH, stETH);
            amountOut = WstETHInterface(AddressBook.WSTETH).wrap(stETH);
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountOut;
        }
        if (tokenOut == AddressBook.cDAI) {
            ERC20(AddressBook.DAI).approve(AddressBook.cDAI, amountIn);
            amountOut = CTokenInterface(AddressBook.cDAI).mint(amountIn);
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountOut;
        }
        if (tokenOut == AddressBook.cETH) {
            AddressBook.cETH.call{ value: amountIn }("");
            emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
            return amountIn;
        }
        if (tokenOut == AddressBook.WETH) {
            return amountIn;
        }

        // approve router to spend tokenIn
        ERC20(tokenIn).approve(AddressBook.UNISWAP_ROUTER, amountIn);
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
        amountOut = SwapRouterLike(AddressBook.UNISWAP_ROUTER).exactInputSingle(params); // executes the swap
        emit Swapped(tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }

    event Swapped(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    fallback() external payable {}
}
