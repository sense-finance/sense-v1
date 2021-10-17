// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { Hevm } from "./Hevm.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { Divider } from "../../Divider.sol";
import { Periphery } from "../../Periphery.sol";
import {GClaimManager} from "../../modules/GClaimManager.sol";
import { Claim } from "../../tokens/Claim.sol";
import { BaseFactory } from "../../feeds/BaseFactory.sol";

contract User {
    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

    MockToken stable;
    MockToken target;
    Divider divider;
    Periphery periphery;
    GClaimManager gClaimManager;
    BaseFactory factory;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    struct Backfill {
        address usr; // address of the backfilled user
        uint256 scale; // scale value to backfill for usr
    }

    function setFactory(BaseFactory _factory) public {
        factory = _factory;
    }

    function setStable(MockToken _token) public {
        stable = _token;
    }

    function setTarget(MockToken _token) public {
        target = _token;
    }

    function setDivider(Divider _divider) public {
        divider = _divider;
    }

    function setPeriphery(Periphery _periphery) public {
        periphery = _periphery;
        gClaimManager = periphery.gClaimManager();
    }

    function doDeployFeed (address _target) public returns (address clone, address twrapper){
        return factory.deployFeed(_target);
    }

    function doTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        return MockToken(token).transferFrom(from, to, amount);
    }

    function doTransfer(address token, address to, uint256 amount) public returns (bool) {
        return MockToken(token).transfer(to, amount);
    }

    function doApprove(address token, address recipient, uint256 amount) public returns (bool) {
        return MockToken(token).approve(recipient, amount);
    }

    function doApprove(address token, address guy) public returns (bool) {
        return MockToken(token).approve(guy, type(uint256).max);
    }

    function doAllowance(address token, address owner, address spender) public view returns (uint256) {
        return MockToken(token).allowance(owner, spender);
    }

    function doBalanceOf(address token, address who) public view returns (uint256) {
        return MockToken(token).balanceOf(who);
    }

    function doMint(address token, uint256 wad) public {
        MockToken(token).mint(address(this), wad);
    }

    function doMint(address token, address guy, uint256 wad) public {
        MockToken(token).mint(guy, wad);
    }

    function doSetFeed(address feed, bool isOn) public {
        divider.setFeed(feed, isOn);
    }

    function doSponsorSeries(address feed, uint256 maturity) public returns (address zero, address claim) {
        (zero, claim) = periphery.sponsorSeries(feed, maturity);
    }

    function doSettleSeries(address feed, uint256 maturity) public {
        divider.settleSeries(feed, maturity);
    }

    function doIssue(address feed, uint256 maturity, uint256 balance) public {
        divider.issue(feed, maturity, balance);
    }

    function doCombine(address feed, uint256 maturity, uint256 balance) public {
        divider.combine(feed, maturity, balance);
    }

    function doBackfillScale(address feed, uint256 maturity, uint256 scale, Divider.Backfill[] memory backfills) public {
        divider.backfillScale(feed, maturity, scale, backfills);
    }

    function doRedeemZero(address feed, uint256 maturity, uint256 balance) public {
        return divider.redeemZero(feed, maturity, balance);
    }

    function doCollect(address claim) public returns (uint256 collected) {
        collected = Claim(claim).collect();
    }

    function doJoin(address feed, uint256 maturity, uint256 balance) public {
        gClaimManager.join(feed, maturity, balance);
    }

    function doExit(address feed, uint256 maturity, uint256 balance) public {
        gClaimManager.exit(feed, maturity, balance);
    }

    function doSwapTargetForZeros(address feed, uint256 maturity, uint256 balance, uint256 backfill) public {
        periphery.swapTargetForZeros(feed, maturity, balance, backfill);
    }
    function doSwapTargetForClaims(address feed, uint256 maturity, uint256 balance) public {
        periphery.swapTargetForClaims(feed, maturity, balance);
    }
    function doSwapZerosForTarget(address feed, uint256 maturity, uint256 balance) public {
        periphery.swapZerosForTarget(feed, maturity, balance);
    }
    function doSwapClaimsForTarget(address feed, uint256 maturity, uint256 balance) public {
        periphery.swapClaimsForTarget(feed, maturity, balance);
    }

}