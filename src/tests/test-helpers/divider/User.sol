pragma solidity ^0.8.6;

import "../TestToken.sol";
import "../../../Divider.sol";

contract User {
    TestToken stableToken; // stable token
    TestToken target; // stable token
    Divider divider;

    function setStableToken(TestToken _token) public {
        stableToken = _token;
    }

    function setTargetToken(TestToken _token) public {
        target = _token;
    }

    function setDivider(Divider _divider) public {
        divider = _divider;
    }

    function doTransferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        return stableToken.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint256 amount) public returns (bool) {
        return stableToken.transfer(to, amount);
    }

    function doApproveStable(address recipient, uint256 amount) public returns (bool) {
        return stableToken.approve(recipient, amount);
    }

    function doApproveStable(address guy) public returns (bool) {
        return stableToken.approve(guy, type(uint256).max);
    }

    function doApproveTarget(address recipient, uint256 amount) public returns (bool) {
        return target.approve(recipient, amount);
    }

    function doApproveTarget(address guy) public returns (bool) {
        return target.approve(guy, type(uint256).max);
    }

    function doAllowance(address owner, address spender) public view returns (uint256) {
        return stableToken.allowance(owner, spender);
    }

    function doBalanceOf(address who) public view returns (uint256) {
        return stableToken.balanceOf(who);
    }

    function doMintStable(uint256 wad) public {
        stableToken.mint(address(this), wad);
    }

    function doMintStable(address guy, uint256 wad) public {
        stableToken.mint(guy, wad);
    }

    function doMintTarget(uint256 wad) public {
        target.mint(address(this), wad);
    }

    function doMintTarget(address guy, uint256 wad) public {
        target.mint(guy, wad);
    }

    function doSetFeed(address feed, bool isOn) public {
        divider.setFeed(feed, isOn);
    }

    function doInitSeries(address feed, uint256 maturity) public returns (address zero, address claim) {
        return divider.initSeries(feed, maturity);
    }

    function doSettleSeries(address feed, uint256 maturity) public {
        return divider.settleSeries(feed, maturity);
    }

    function doIssue(address feed, uint256 maturity, uint256 balance) public {
        return divider.issue(feed, maturity, balance);
    }

    function doCombine(address feed, uint256 maturity, uint256 balance) public {
        return divider.combine(feed, maturity, balance);
    }

    function doBackfillScale(address feed, uint256 maturity, uint256 scale, uint256[] memory values, address[] memory accounts) public {
        return divider.backfillScale(feed, maturity, scale, values, accounts);
    }

    function doRedeemZero(address feed, uint256 maturity, uint256 balance) public {
        return divider.redeemZero(feed, maturity, balance);
    }

    function doCollect(address claim) public returns (uint256 collected) {
        return Claim(claim).collect();
    }
}