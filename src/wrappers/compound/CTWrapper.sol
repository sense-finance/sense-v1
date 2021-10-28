// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { BaseTWrapper } from "../BaseTWrapper.sol";

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

// Based on CErc20Interface in https://github.com/compound-finance/compound-protocol/blob/v2.8.1/contracts/CTokenInterfaces.sol
// and documentation at https://compound.finance/docs/ctokens
interface CTokenInterfaces {
    /// Underlying asset for this CToken
    function underlying() external view returns (address);

    /// The mint function transfers an asset into the protocol, which begins accumulating interest based
    /// on the current Supply Rate for the asset. The user receives a quantity of cTokens equal to the
    /// underlying tokens supplied, divided by the current Exchange Rate.
    /// @param mintAmount The amount of the asset to be supplied, in units of the underlying asset.
    /// @return 0 on success, otherwise an Error code
    function mint(uint mintAmount) external returns (uint);

    /// The redeem function converts a specified quantity of cTokens into the underlying asset, and returns
    /// them to the user. The amount of underlying tokens received is equal to the quantity of cTokens redeemed,
    /// multiplied by the current Exchange Rate. The amount redeemed must be less than the user's Account Liquidity
    /// and the market's available liquidity.
    /// @param redeemTokens The number of cTokens to be redeemed.
    /// @return 0 on success, otherwise an Error code
    function redeem(uint redeemTokens) external returns (uint);
}

// @title feed contract for cTokens
contract CTWrapper is BaseTWrapper {
    using FixedMath for uint256;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }

    function wrapUnderlying(uint256 uBal) external virtual override returns (uint256) {
        uint256 tBalBefore = ERC20(target).balanceOf(address(this));
        require(CTokenInterfaces(target).mint(uBal) == 0, "Mint failed");
        uint256 tBalAfter = ERC20(target).balanceOf(address(this));
        return tBalAfter - tBalBefore;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        uint256 uBalBefore = ERC20(CTokenInterfaces(target).underlying()).balanceOf(address(this));
        require(CTokenInterfaces(target).redeem(tBal) == 0, "Redeem failed");
        uint256 uBalAfter = ERC20(CTokenInterfaces(target).underlying()).balanceOf(address(this));
        return uBalAfter - uBalBefore;
    }
}
