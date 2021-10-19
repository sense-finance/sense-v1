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

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        reward.mint(address(twrapper), 50 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);

        bob.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        bob.doIssue(address(feed), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
    }

    function testDistributionSimple() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(twrapper), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doCombine(address(feed), maturity, ERC20(claim).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(twrapper), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        reward.mint(address(twrapper), 50 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        bob.doIssue(address(feed), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(twrapper), 50e18);

        alice.doIssue(address(feed), maturity, 20 * 1e18);
        bob.doIssue(address(feed), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(twrapper), 30 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        bob.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);

        alice.doCombine(address(feed), maturity, ERC20(claim).balanceOf(address(alice)));
    }

    function testDistributionSimpleCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);

        reward.mint(address(twrapper), 60 * 1e18);

        bob.doCollect(claim);
        assertClose(reward.balanceOf(address(bob)), 24 * 1e18);
    }

    function testDistributionCollectAndTransferMultiStep() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        // bob issues 40, now the pool is 40% bob and 60% alice
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(twrapper), 60 * 1e18);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(feed), maturity, 100 * 1e18);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(twrapper), 100 * 1e18);

        // bob transfers all of his Claims to jim
        // now the pool is 70% jim and 30% alice
        bob.doTransfer(claim, address(jim), ERC20(claim).balanceOf(address(bob)));
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertEq(reward.balanceOf(address(bob)), 44 * 1e18);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertEq(reward.balanceOf(address(jim)), 50 * 1e18);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        alice.doCollect(claim);
        assertEq(reward.balanceOf(address(alice)), 66 * 1e18);

        // now if another airdop happens, jim should get shares proportional to his new claim balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(twrapper), 100 * 1e18);
        jim.doCollect(claim);
        assertEq(reward.balanceOf(address(jim)), 120 * 1e18);
        alice.doCollect(claim);
        assertEq(reward.balanceOf(address(alice)), 96 * 1e18);

    }
}
