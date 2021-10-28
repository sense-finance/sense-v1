// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockToken.sol";
import { BaseFeed as Feed } from "../../../feeds/BaseFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

// Internal
import { BaseTWrapper } from "../../../wrappers/BaseTWrapper.sol";

/// @notice
contract MockTWrapper is BaseTWrapper {
    using FixedMath for uint256;

    address public feed;

    /* ========== MUTATIVE FUNCTIONS ========== */
    function _claimReward() internal override virtual {
//        MockToken(reward).mint(address(this), 1e18);
    }

    function wrapUnderlying(uint256 uBal) external virtual override returns (uint256) {
        (, uint256 lvalue) = Feed(feed).lscale();
        MockToken(MockTarget(target).underlying()).burn(address(this), uBal); // this would be an approve call to the protocol to withdraw the underlying
        uint256 tBase = 10**MockTarget(target).decimals();
        uint256 mintAmount = uBal.fdiv(lvalue, tBase);
        MockToken(target).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        (, uint256 lvalue) = Feed(feed).lscale();
        MockTarget(target).burn(address(this), tBal); // this would be an approve call to the protocol to withdraw the target
        uint256 tBase = 10**MockTarget(target).decimals();
        uint256 mintAmount = tBal.fmul(lvalue, tBase);
        MockToken(MockTarget(target).underlying()).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function setFeed(address _feed) external {
        feed = _feed;
    }

}
