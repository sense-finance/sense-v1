// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { BaseTWrapper } from "../wrappers/BaseTWrapper.sol";
import { Claim } from "../tokens/Claim.sol";
import { MockTWrapper } from "./test-helpers/mocks/MockTWrapper.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { Errors } from "../libs/errors.sol";

contract Wrappers is TestHelper {
    function testDeployWrapper() public {
        BaseTWrapper twrapper = new BaseTWrapper();
        twrapper.initialize(address(target), address(divider), address(reward));

        assertEq(twrapper.target(), address(target));
        assertEq(twrapper.divider(), address(divider));
        assertEq(twrapper.reward(), address(reward));
    }

    function testDistribution() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        BaseTWrapper twrapper = new BaseTWrapper();
        twrapper.initialize(address(target), address(divider), address(reward));

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        twrapper.distribute(address(feed), maturity, address(bob));

        reward.mint(address(twrapper), 50 * 1e18);

        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);

        twrapper.distribute(address(feed), maturity, address(bob));
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        twrapper.distribute(address(feed), maturity, address(alice));
        twrapper.distribute(address(feed), maturity, address(bob));
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
    }

    function testDistributionSimple() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        BaseTWrapper twrapper = new BaseTWrapper();
        twrapper.initialize(address(target), address(divider), address(reward));

        alice.doIssue(address(feed), maturity, 100 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(twrapper), 10 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 100 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doCombine(address(feed), maturity, ERC20(claim).balanceOf(address(alice)));
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 50 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(twrapper), 10 * 1e18);
        alice.doIssue(address(feed), maturity, 10 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        BaseTWrapper twrapper = new BaseTWrapper();
        twrapper.initialize(address(target), address(divider), address(reward));

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        twrapper.distribute(address(feed), maturity, address(bob));

        reward.mint(address(twrapper), 50 * 1e18);

        twrapper.distribute(address(feed), maturity, address(alice));
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        twrapper.distribute(address(feed), maturity, address(bob));
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(twrapper), 50e18);

        alice.doIssue(address(feed), maturity, 20 * 1e18);
        twrapper.distribute(address(feed), maturity, address(alice));
        twrapper.distribute(address(feed), maturity, address(bob));
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(twrapper), 30 * 1e18);

        twrapper.distribute(address(feed), maturity, address(alice));
        twrapper.distribute(address(feed), maturity, address(bob));
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);
    }
}
