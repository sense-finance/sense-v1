import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";
import { Periphery } from "../Periphery.sol";

import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

library PeripheryLogic {
    using SafeTransferLib for ERC20;

    IPermit2 public constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        // 0x ExchangeProxy address. See https://docs.0x.org/developer-resources/contract-addresses
    address public constant exchangeProxy = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

        /// @notice ETH address
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // @dev Swaps ETH->ERC20, ERC20->ERC20 or ERC20->ETH held by this contract using a 0x-API quote
    function fillQuote(Periphery.SwapQuote calldata quote) external returns (uint256 boughtAmount, uint256 sellAmount) {
        if (quote.sellToken == quote.buyToken) return (0, 0); // No swap if the tokens are the same.
        if (quote.swapTarget != exchangeProxy) revert Errors.InvalidExchangeProxy();
 
        // Give `spender` an infinite allowance to spend this contract's `sellToken`.
        if (address(quote.sellToken) != ETH)
            ERC20(address(quote.sellToken)).safeApprove(quote.spender, type(uint256).max);

        uint256 sellAmount = address(quote.sellToken) == ETH
            ? address(this).balance
            : quote.sellToken.balanceOf(address(this));

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, bytes memory res) = quote.swapTarget.call{ value: msg.value }(quote.swapCallData);
        if (!success) revert Errors.ZeroExSwapFailed(res);

        // We assume the Periphery does not hold tokens so boughtAmount is always it's balance
        boughtAmount = address(quote.buyToken) == ETH ? address(this).balance : quote.buyToken.balanceOf(address(this));
        sellAmount =
            sellAmount -
            (address(quote.sellToken) == ETH ? address(this).balance : quote.sellToken.balanceOf(address(this)));
        if (boughtAmount == 0 || sellAmount == 0) revert Errors.ZeroSwapAmt();
    }

    function transferFrom(
        Periphery.PermitData memory permit,
        address token,
        uint256 amt
    ) external {

        // Generate calldata for a standard safeTransferFrom call.
        bytes memory inputData = abi.encodeCall(ERC20.transferFrom, (msg.sender, address(this), amt));

        bool success; // Call the token contract as normal, capturing whether it succeeded.
        assembly {
            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(eq(mload(0), 1), iszero(returndatasize())),
                // Counterintuitively, this call() must be positioned after the or() in the
                // surrounding and() because and() evaluates its arguments from right to left.
                // We use 0 and 32 to copy up to 32 bytes of return data into the first slot of scratch space.
                call(gas(), token, 0, add(inputData, 32), mload(inputData), 0, 32)
            )
        }

        // We'll fall back to using Permit2 if calling transferFrom on the token directly reverted.
        if (!success)
            permit2.permitTransferFrom(
                permit.msg,
                IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: amt }),
                msg.sender,
                permit.sig
            );
    }

    function transfer(
        ERC20 token,
        address receiver,
        uint256 amt
    ) external {
        if (amt > 0) {
            if (address(token) == ETH) {
                (bool sent, ) = receiver.call{ value: amt }("");
                if (!sent) revert Errors.TransferFailed();
            } else {
                token.safeTransfer(receiver, amt);
            }
        }
    }
}

