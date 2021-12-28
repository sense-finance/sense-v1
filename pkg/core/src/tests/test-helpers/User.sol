// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Hevm } from "./Hevm.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { Divider } from "../../Divider.sol";
import { Periphery } from "../../Periphery.sol";
import { GClaimManager } from "../../modules/GClaimManager.sol";
import { Claim } from "../../tokens/Claim.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";

contract User {
    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    MockToken stake;
    MockToken target;
    Divider divider;
    Periphery periphery;
    GClaimManager public gClaimManager;
    BaseFactory factory;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    struct Backfill {
        address usr; // address of the backfilled user
        uint256 scale; // scale value to backfill for usr
    }

    function setFactory(BaseFactory _factory) public {
        factory = _factory;
    }

    function setStake(MockToken _token) public {
        stake = _token;
    }

    function setTarget(MockToken _token) public {
        target = _token;
    }

    function setDivider(Divider _divider) public {
        divider = _divider;
    }

    function setPeriphery(Periphery _periphery) public {
        periphery = _periphery;
        gClaimManager = new GClaimManager(address(divider));
    }

    function doDeployAdapter(address _target) public returns (address clone) {
        return factory.deployAdapter(_target);
    }

    function doTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        return MockToken(token).transferFrom(from, to, amount);
    }

    function doTransfer(
        address token,
        address to,
        uint256 amount
    ) public returns (bool) {
        return MockToken(token).transfer(to, amount);
    }

    function doApprove(
        address token,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        return MockToken(token).approve(recipient, amount);
    }

    function doApprove(address token, address guy) public returns (bool) {
        return MockToken(token).approve(guy, type(uint256).max);
    }

    function doAllowance(
        address token,
        address owner,
        address spender
    ) public view returns (uint256) {
        return MockToken(token).allowance(owner, spender);
    }

    function doBalanceOf(address token, address who) public view returns (uint256) {
        return MockToken(token).balanceOf(who);
    }

    function doMint(address token, uint256 wad) public {
        MockToken(token).mint(address(this), wad);
    }

    function doMint(
        address token,
        address guy,
        uint256 wad
    ) public {
        MockToken(token).mint(guy, wad);
    }

    function doSetAdapter(address adapter, bool isOn) public {
        divider.setAdapter(adapter, isOn);
    }

    function doAddAdapter(address adapter) public {
        divider.addAdapter(adapter);
    }

    function doSponsorSeries(address adapter, uint48 maturity) public returns (address zero, address claim) {
        (zero, claim) = periphery.sponsorSeries(adapter, maturity);
    }

    function doSettleSeries(address adapter, uint48 maturity) public {
        divider.settleSeries(adapter, maturity);
    }

    function doIssue(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public returns (uint256) {
        return divider.issue(adapter, maturity, balance);
    }

    function doCombine(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public returns (uint256) {
        return divider.combine(adapter, maturity, balance);
    }

    function doBackfillScale(
        address adapter,
        uint48 maturity,
        uint256 scale,
        address[] calldata usrs,
        uint256[] calldata lscales
    ) public {
        divider.backfillScale(adapter, maturity, scale, usrs, lscales);
    }

    function doRedeemZero(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public returns (uint256 redeemed) {
        redeemed = divider.redeemZero(adapter, maturity, balance);
    }

    function doCollect(address claim) public returns (uint256 collected) {
        collected = Claim(claim).collect();
    }

    function doJoin(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public {
        gClaimManager.join(adapter, maturity, balance);
    }

    function doExit(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public {
        gClaimManager.exit(adapter, maturity, balance);
    }

    function doSwapTargetForZeros(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapTargetForZeros(adapter, maturity, balance, minAccepted);
    }

    function doSwapUnderlyingForZeros(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapUnderlyingForZeros(adapter, maturity, balance, minAccepted);
    }

    function doSwapTargetForClaims(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapTargetForClaims(adapter, maturity, balance, minAccepted);
    }

    function doSwapUnderlyingForClaims(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapUnderlyingForClaims(adapter, maturity, balance, minAccepted);
    }

    function doSwapZerosForTarget(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapZerosForTarget(adapter, maturity, balance, minAccepted);
    }

    function doSwapZerosForUnderlying(
        address adapter,
        uint48 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapZerosForUnderlying(adapter, maturity, balance, minAccepted);
    }

    function doSwapClaimsForTarget(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public {
        periphery.swapClaimsForTarget(adapter, maturity, balance);
    }

    function doSwapClaimsForUnderlying(
        address adapter,
        uint48 maturity,
        uint256 balance
    ) public {
        periphery.swapClaimsForUnderlying(adapter, maturity, balance);
    }

    function doAddLiquidityFromTarget(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint8 mode
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return periphery.addLiquidityFromTarget(adapter, maturity, tBal, mode);
    }

    function doAddLiquidityFromUnderlying(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint8 mode
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return periphery.addLiquidityFromUnderlying(adapter, maturity, tBal, mode);
    }

    function doRemoveLiquidityToTarget(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint256[] memory minAmountsOut,
        uint256 minAmount
    ) public returns (uint256) {
        return periphery.removeLiquidityToTarget(adapter, maturity, tBal, minAmountsOut, minAmount);
    }

    function doMigrateLiquidity(
        address srcAdapter,
        address dstAdapter,
        uint48 srcMaturity,
        uint48 dstMaturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        uint8 mode
    )
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return
            periphery.migrateLiquidity(
                srcAdapter,
                dstAdapter,
                srcMaturity,
                dstMaturity,
                lpBal,
                minAmountsOut,
                minAccepted,
                mode
            );
    }
}
