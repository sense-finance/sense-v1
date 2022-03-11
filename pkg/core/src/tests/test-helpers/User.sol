// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { Hevm } from "./Hevm.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockAdapter } from "./mocks/MockAdapter.sol";
import { Divider } from "../../Divider.sol";
import { Periphery } from "../../Periphery.sol";
import { GYTManager } from "../../modules/GYTManager.sol";
import { YT } from "../../tokens/YT.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";

contract User {
    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    MockToken stake;
    MockToken target;
    Divider divider;
    Periphery periphery;
    GYTManager public gYTManager;
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
        gYTManager = new GYTManager(address(divider));
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

    function doSponsorSeries(address adapter, uint256 maturity) public returns (address pt, address yt) {
        (pt, yt) = periphery.sponsorSeries(adapter, maturity, true);
    }

    function doSponsorSeriesWithoutPool(address adapter, uint256 maturity) public returns (address pt, address yt) {
        (pt, yt) = periphery.sponsorSeries(adapter, maturity, false);
    }

    function doSettleSeries(address adapter, uint256 maturity) public {
        divider.settleSeries(adapter, maturity);
    }

    function doIssue(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public returns (uint256) {
        return divider.issue(adapter, maturity, balance);
    }

    function doCombine(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public returns (uint256) {
        return divider.combine(adapter, maturity, balance);
    }

    function doBackfillScale(
        address adapter,
        uint256 maturity,
        uint256 scale,
        address[] calldata usrs,
        uint256[] calldata lscales
    ) public {
        divider.backfillScale(adapter, maturity, scale, usrs, lscales);
    }

    function doRedeemPrincipal(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public returns (uint256 redeemed) {
        redeemed = divider.redeem(adapter, maturity, balance);
    }

    function doCollect(address yt) public returns (uint256 collected) {
        collected = YT(yt).collect();
    }

    function doJoin(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        gYTManager.join(adapter, maturity, balance);
    }

    function doExit(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        gYTManager.exit(adapter, maturity, balance);
    }

    function doswapTargetForPTs(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapTargetForPTs(adapter, maturity, balance, minAccepted);
    }

    function doSwapUnderlyingForPTs(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapUnderlyingForPTs(adapter, maturity, balance, minAccepted);
    }

    function doSwapTargetForYTs(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapTargetForYTs(adapter, maturity, balance, minAccepted);
    }

    function doSwapUnderlyingForYTs(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapUnderlyingForYTs(adapter, maturity, balance, minAccepted);
    }

    function doSwapPrincipalForTarget(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapPTsForTarget(adapter, maturity, balance, minAccepted);
    }

    function doSwapPrincipalForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 balance,
        uint256 minAccepted
    ) public {
        periphery.swapPTsForUnderlying(adapter, maturity, balance, minAccepted);
    }

    function doSwapYieldForTarget(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        periphery.swapYTsForTarget(adapter, maturity, balance);
    }

    function doSwapYieldForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        periphery.swapYTsForUnderlying(adapter, maturity, balance);
    }

    function doAddLiquidityFromTarget(
        address adapter,
        uint256 maturity,
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
        uint256 maturity,
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

    function doRemoveLiquidity(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        bool swap
    ) public returns (uint256, uint256) {
        return periphery.removeLiquidity(adapter, maturity, tBal, minAmountsOut, minAccepted, swap);
    }

    function doMigrateLiquidity(
        address srcAdapter,
        address dstAdapter,
        uint256 srcMaturity,
        uint256 dstMaturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        uint8 mode,
        bool swap
    )
        public
        returns (
            uint256,
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
                mode,
                true
            );
    }

    function doAdapterInitSeries(
        address adapter,
        uint256 maturity,
        address sponsor
    ) public {
        MockAdapter(adapter).doInitSeries(maturity, sponsor);
    }

    function doAdapterIssue(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        MockAdapter(adapter).doIssue(maturity, balance);
    }

    function doAdapterCombine(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public returns (uint256) {
        return MockAdapter(adapter).doCombine(maturity, balance);
    }

    function doAdapterRedeemPrincipal(
        address adapter,
        uint256 maturity,
        uint256 balance
    ) public {
        divider.combine(adapter, maturity, balance);
    }
}
