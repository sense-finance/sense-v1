// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Errors } from "../libs/Errors.sol";
import { BaseFeed } from "../feeds/BaseFeed.sol";
import { Divider } from "../Divider.sol";

import { MockFeed } from "./test-helpers/mocks/MockFeed.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract FakeFeed is BaseFeed {
    function _scale() internal virtual override returns (uint256 _value) {
        _value = 100e18;
    }

    function underlying() external virtual override returns (address) {
        return address(1);
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function doSetFeed(Divider d, address _feed) public {
        d.setFeed(_feed, true);
    }
}

contract Feeds is TestHelper {
    using FixedMath for uint256;

    function testFeedHasParams() public {
        MockToken target = new MockToken("Compound Dai", "cDAI", 18);
        MockFeed feed = new MockFeed();

        BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
            target: address(target),
            stake: address(stake),
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY
        });

        feed.initialize(address(divider), feedParams);

        assertEq(feed.name(), "Compound Dai Feed");
        assertEq(feed.symbol(), "cDAI-feed");
        (
            ,
            address oracle,
            uint256 delta,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm
        ) = BaseFeed(feed).feedParams();
        assertEq(feed.getTarget(), address(target));
        assertEq(feed.divider(), address(divider));
        assertEq(delta, DELTA);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
    }

    function testScale() public {
        assertEq(feed.scale(), feed.INITIAL_VALUE());
    }

    function testScaleMultipleTimes() public {
        assertEq(feed.scale(), feed.INITIAL_VALUE());
        assertEq(feed.scale(), feed.INITIAL_VALUE());
        assertEq(feed.scale(), feed.INITIAL_VALUE());
    }

    function testScaleIfEqualDelta() public {
        uint256[] memory startingScales = new uint256[](4);
        startingScales[0] = 2e20; // 200 WAD
        startingScales[1] = 1e18; // 1 WAD
        startingScales[2] = 1e17; // 0.1 WAD
        startingScales[3] = 4e15; // 0.004 WAD
        for (uint256 i = 0; i < startingScales.length; i++) {
            MockFeed localFeed = new MockFeed();

            BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
                target: address(target),
                stake: address(stake),
                oracle: ORACLE,
                delta: DELTA,
                ifee: ISSUANCE_FEE,
                stakeSize: STAKE_SIZE,
                minm: MIN_MATURITY,
                maxm: MAX_MATURITY
            });

            localFeed.initialize(address(divider), feedParams);

            uint256 startingScale = startingScales[i];

            hevm.warp(0);
            localFeed.setScale(startingScale);
            // Set starting scale and store it as lscale
            localFeed.scale();
            (uint256 ltimestamp, uint256 lvalue) = localFeed._lscale();
            assertEq(lvalue, startingScale);

            hevm.warp(1 days);

            // 86400 (1 day)
            uint256 timeDiff = block.timestamp - ltimestamp;
            // Find the scale value would bring us right up to the acceptable growth per second (delta)?
            // Equation rationale:
            //      *  DELTA is the max tolerable percent growth in the scale value per second.
            //      *  So, we multiply that by the number of seconds that have passed.
            //      *  And multiply that result by the previous scale value to
            //         get the max amount of scale that we say can have grown.
            //         We are functionally doing `maxPercentIncrease * value`, which gets
            //         us the max *amount* that the value could have increased by.
            //      *  Then add that max increase to the original value to get the maximum possible.
            uint256 maxScale = (DELTA * timeDiff).fmul(lvalue, 10**ERC20(localFeed.getTarget()).decimals()) + lvalue;

            // Set max scale and ensure calling `scale` with it doesn't revert
            localFeed.setScale(maxScale);
            localFeed.scale();

            // add 1 more day
            hevm.warp(2 days);
            (ltimestamp, lvalue) = localFeed._lscale();
            timeDiff = block.timestamp - ltimestamp;
            maxScale = (DELTA * timeDiff).fmul(lvalue, 10**ERC20(localFeed.getTarget()).decimals()) + lvalue;
            localFeed.setScale(maxScale);
            localFeed.scale();
        }
    }

    function testCantScaleIfMoreThanDelta() public {
        uint256[] memory startingScales = new uint256[](4);
        startingScales[0] = 2e20; // 200 WAD
        startingScales[1] = 1e18; // 1 WAD
        startingScales[2] = 1e17; // 0.1 WAD
        startingScales[3] = 4e15; // 0.004 WAD
        for (uint256 i = 0; i < startingScales.length; i++) {
            MockFeed localFeed = new MockFeed();
            BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
                target: address(target),
                stake: address(stake),
                oracle: ORACLE,
                delta: DELTA,
                ifee: ISSUANCE_FEE,
                stakeSize: STAKE_SIZE,
                minm: MIN_MATURITY,
                maxm: MAX_MATURITY
            });

            localFeed.initialize(address(divider), feedParams);
            uint256 startingScale = startingScales[i];

            hevm.warp(0);
            localFeed.setScale(startingScale);
            // Set starting scale and store it as lscale
            localFeed.scale();
            (uint256 ltimestamp, uint256 lvalue) = localFeed._lscale();
            assertEq(lvalue, startingScale);

            hevm.warp(1 days);

            // 86400 (1 day)
            uint256 timeDiff = block.timestamp - ltimestamp;
            // find the scale value would bring us right up to the acceptable growth per second (delta)?
            uint256 maxScale = (DELTA * timeDiff).fmul(lvalue, 10**ERC20(localFeed.getTarget()).decimals()) + lvalue;

            // `maxScale * 1.000001` (adding small numbers wasn't enough to trigger the delta check as they got rounded
            // away in wdivs)
            localFeed.setScale(maxScale.fmul(1000001e12, 10**ERC20(localFeed.getTarget()).decimals()));

            try localFeed.scale() {
                fail();
            } catch Error(string memory error) {
                assertEq(error, Errors.InvalidScaleValue);
            }
        }
    }

    function testCantAddCustomFeedToDivider() public {
        MockToken newTarget = new MockToken("Compound USDC", "cUSDC", 18);
        FakeFeed fakeFeed = new FakeFeed();
        BaseFeed.FeedParams memory feedParams = BaseFeed.FeedParams({
            target: address(target),
            stake: address(stake),
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY
        });

        fakeFeed.initialize(address(divider), feedParams);
        try fakeFeed.doSetFeed(divider, address(fakeFeed)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.NotAuthorized);
        }
    }

    // distribution tests
    function testDistribution() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        reward.mint(address(feed), 50 * 1e18);

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

        reward.mint(address(feed), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doCombine(address(feed), maturity, ERC20(claim).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(feed), 10 * 1e18);

        alice.doIssue(address(feed), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        feed.setScale(1e18);

        alice.doIssue(address(feed), maturity, 60 * 1e18);
        bob.doIssue(address(feed), maturity, 40 * 1e18);

        reward.mint(address(feed), 50 * 1e18);

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

        reward.mint(address(feed), 50e18);

        alice.doIssue(address(feed), maturity, 20 * 1e18);
        bob.doIssue(address(feed), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(feed), 30 * 1e18);

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

        reward.mint(address(feed), 60 * 1e18);

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
        reward.mint(address(feed), 60 * 1e18);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(feed), maturity, 100 * 1e18);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(feed), 100 * 1e18);

        // bob transfers all of his Claims to jim
        // now the pool is 70% jim and 30% alice
        bob.doTransfer(claim, address(jim), ERC20(claim).balanceOf(address(bob)));
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertClose(reward.balanceOf(address(bob)), 44 * 1e18);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertClose(reward.balanceOf(address(jim)), 50 * 1e18);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        alice.doCollect(claim);
        assertClose(reward.balanceOf(address(alice)), 66 * 1e18);

        // now if another airdop happens, jim should get shares proportional to his new claim balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(feed), 100 * 1e18);
        jim.doCollect(claim);
        assertClose(reward.balanceOf(address(jim)), 120 * 1e18);
        alice.doCollect(claim);
        assertClose(reward.balanceOf(address(alice)), 96 * 1e18);
    }
}
