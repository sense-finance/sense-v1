// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Divider } from "../../Divider.sol";
import { YT } from "../../tokens/YT.sol";

import { MockCropsAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockCropsFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { MockClaimer } from "../test-helpers/mocks/MockClaimer.sol";
import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { Constants } from "../test-helpers/Constants.sol";

contract CropsAdapters is TestHelper {
    using FixedMath for uint256;

    MockToken internal reward2;
    MockCropsAdapter internal cropsAdapter;
    MockCropsFactory internal cropsFactory;
    MockTargetLike internal aTarget;

    // reward tokens
    address[] public rewardTokens;

    function setUp() public virtual override {
        ISSUANCE_FEE = 0; // super.setUp will create an adapter with 0 fee to simplify tests math
        MAX_MATURITY = 52 weeks; // super.setUp will create an adapter with 12 month max maturity

        super.setUp();
        reward2 = new MockToken("Reward Token 2", "RT2", 6);
        aTarget = MockTargetLike(deployMockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals));

        rewardTokens = [address(reward), address(reward2)];
        cropsFactory = MockCropsFactory(deployCropsFactory(address(aTarget), rewardTokens, true));
        address a = periphery.deployAdapter(address(cropsFactory), address(aTarget), abi.encode(rewardTokens)); // deploy & onboard target through Periphery
        cropsAdapter = MockCropsAdapter(a);
        divider.setGuard(address(cropsAdapter), 10 * 2**128);

        initUser(alice, aTarget, MAX_TARGET);
        initUser(bob, aTarget, MAX_TARGET);
        initUser(jim, aTarget, MAX_TARGET);

        // freeze scale to 1e18 (only for no 4626 targets)
        if (!is4626Target) cropsAdapter.setScale(1e18);
    }

    function testAdapterHasParams() public {
        MockToken underlying = new MockToken("Dai", "DAI", 18);
        MockTargetLike target = MockTargetLike(
            deployMockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals)
        );

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: ORACLE,
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: DEFAULT_LEVEL
        });

        MockCropsAdapter cropsAdapter = new MockCropsAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams,
            rewardTokens
        );

        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = cropsAdapter
            .adapterParams();
        assertEq(cropsAdapter.rewardTokens(0), address(reward));
        assertEq(cropsAdapter.rewardTokens(1), address(reward2));
        assertEq(cropsAdapter.name(), "Compound Dai Adapter");
        assertEq(cropsAdapter.symbol(), "cDAI-adapter");
        assertEq(cropsAdapter.target(), address(target));
        assertEq(cropsAdapter.underlying(), address(underlying));
        assertEq(cropsAdapter.divider(), address(divider));
        assertEq(cropsAdapter.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(cropsAdapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(cropsAdapter.mode(), MODE);
    }

    function testExtractToken() public {
        // can extract someReward
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        someReward.mint(address(cropsAdapter), 1e18);
        assertEq(someReward.balanceOf(address(cropsAdapter)), 1e18);

        hevm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(someReward), Constants.REWARDS_RECIPIENT, 1e18);

        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 0);
        // anyone can call extract token
        hevm.prank(address(0xfede));
        cropsAdapter.extractToken(address(someReward));
        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 1e18);

        (address target, address stake, ) = cropsAdapter.getStakeAndTarget();

        // can NOT extract stake
        hevm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        cropsAdapter.extractToken(address(stake));

        // can NOT extract target
        hevm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        cropsAdapter.extractToken(address(target));

        // can NOT extract reward token
        hevm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        cropsAdapter.extractToken(address(reward));

        // can NOT extract reward2 token
        hevm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        cropsAdapter.extractToken(address(reward2));
    }

    // distribution tests

    function testFuzzDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        hevm.expectEmit(true, true, true, false);
        emit Distributed(alice, address(reward), 0);

        hevm.expectEmit(true, true, true, false);
        emit Distributed(alice, address(reward2), 0);

        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 0);
        assertClose(ERC20(reward2).balanceOf(bob), 0 * 1e6);

        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e6);
    }

    function testFuzzSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 20 * 1e6);
    }

    function testFuzzProportionalDistribution() public {
        // assumeBounds(tBal);
        uint256 tBal = 100 * 1e18;
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 0);
        assertClose(ERC20(reward2).balanceOf(bob), 0);

        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e6);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (20 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e6);

        reward.mint(address(cropsAdapter), 30 * 1e18);
        reward2.mint(address(cropsAdapter), 30 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 80 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 80 * 1e6);
        assertClose(ERC20(reward).balanceOf(bob), 50 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 50 * 1e6);

        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
    }

    function testFuzzSimpleDistributionAndCollect(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);

        hevm.prank(bob);
        YT(yt).collect();
        assertClose(reward.balanceOf(bob), 24 * 1e18);
        assertClose(reward2.balanceOf(bob), 24 * 1e6);
    }

    function testFuzzDistributionCollectAndTransferMultiStep(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        // bob issues 40, now the pool is 40% bob and 60% alice
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        hevm.prank(jim);
        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(cropsAdapter), 100 * 1e18);
        reward2.mint(address(cropsAdapter), 100 * 1e6);

        // bob transfers all of his Yield to jim
        // now the pool is 70% jim and 30% alice
        uint256 bytBal = ERC20(yt).balanceOf(bob);
        hevm.prank(bob);
        MockToken(yt).transfer(jim, bytBal);
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertClose(reward.balanceOf(bob), 44 * 1e18);
        assertClose(reward2.balanceOf(bob), 44 * 1e6);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertClose(reward.balanceOf(jim), 50 * 1e18);
        assertClose(reward2.balanceOf(jim), 50 * 1e6);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        YT(yt).collect();
        assertClose(reward.balanceOf(alice), 66 * 1e18);
        assertClose(reward2.balanceOf(alice), 66 * 1e6);

        // now if another airdop happens, jim should get shares proportional to his new yt balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(cropsAdapter), 100 * 1e18);
        reward2.mint(address(cropsAdapter), 100 * 1e6);
        hevm.prank(jim);
        YT(yt).collect();
        assertClose(reward.balanceOf(jim), 120 * 1e18);
        assertClose(reward2.balanceOf(jim), 120 * 1e6);
        YT(yt).collect();
        assertClose(reward.balanceOf(alice), 96 * 1e18);
        assertClose(reward2.balanceOf(alice), 96 * 1e6);
    }

    function testFuzzDistributionAddRewardToken(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        // add new reward token
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));
        hevm.prank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(alice), 0);

        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(alice), 0);

        divider.issue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);
        reward3.mint(address(cropsAdapter), 10 * 1e18);

        divider.issue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 20 * 1e6);
        assertClose(ERC20(reward3).balanceOf(alice), 10 * 1e18);
    }

    function testFuzzDistributionRemoveRewardToken(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        // remove reward token
        rewardTokens.pop();
        hevm.prank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        divider.issue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e6);
    }

    function testFuzzCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint256 tBal) public {
        tBal = uint128(fuzzWithBounds(tBal, 1000, type(uint32).max));
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(cropsAdapter), airdrop);
        reward2.mint(address(cropsAdapter), airdrop);
        YT(yt).collect();
        assertTrue(cropsAdapter.tBalance(alice) > 0);

        reward2.mint(address(cropsAdapter), airdrop);
        hevm.warp(maturity);
        divider.settleSeries(address(cropsAdapter), maturity);
        YT(yt).collect();

        assertEq(cropsAdapter.tBalance(alice), 0);
        uint256 collected = YT(yt).collect(); // try collecting after redemption
        assertEq(collected, 0);
    }

    // reconcile tests

    function testFuzzReconcileMoreThanOnce(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Bob's position
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = bob;

        hevm.expectEmit(true, false, false, false);
        emit Reconciled(bob, 0, maturity);

        cropsAdapter.reconcile(users, maturities);
        cropsAdapter.reconcile(users, maturities);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(bob), 20 * 1e18);
        assertClose(reward2.balanceOf(bob), 20 * 1e18);
    }

    function testFuzzGetMaturedSeriesRewardsIfReconcileAfterMaturity(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Bob's position
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = bob;
        cropsAdapter.reconcile(users, maturities);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(bob), 20 * 1e18);
        assertClose(reward2.balanceOf(bob), 20 * 1e18);
    }

    function testFuzzCantDiluteRewardsIfReconciledInSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);
        assertClose(ERC20(reward2).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e18);

        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e18);

        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 10 * 1e18);

        reward.mint(address(cropsAdapter), 20 * 1e18);
        reward2.mint(address(cropsAdapter), 20 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's position
        assertEq(cropsAdapter.tBalance(alice), (200 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(alice), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = alice;
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.reconciledAmt(alice), (200 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(alice), 0);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        divider.issue(address(cropsAdapter), newMaturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);

        reward.mint(address(cropsAdapter), 30 * 1e18);
        reward2.mint(address(cropsAdapter), 30 * 1e18);

        divider.issue(address(cropsAdapter), newMaturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);

        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
    }

    // On the 2nd Series we issue an amount which is equal to the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstI(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertClose(cropsAdapter.reconciledAmt(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        cropsAdapter.reconcile(users, maturities);

        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Issue an amount equal to the users' `reconciledAmt`
        divider.issue(address(cropsAdapter), newMaturity, (60 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);

        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.prank(bob);
        YT(yt).collect();
        divider.issue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs first and her tBalance should decrement
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
    }

    // On the 2nd Series we issue an amount which is bigger than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertClose(cropsAdapter.reconciledAmt(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        cropsAdapter.reconcile(users, maturities);

        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Issue an amount bigger than the users' `reconciledAmt`
        divider.issue(address(cropsAdapter), newMaturity, (120 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (120 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);

        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (80 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (80 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(newYt).collect();
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), (120 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        assertClose(cropsAdapter.tBalance(bob), (80 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);
    }

    // On the 2nd Series we issue an amount which is smaller than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstIII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertClose(cropsAdapter.reconciledAmt(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        cropsAdapter.reconcile(users, maturities);

        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Issue an amount bigger than the users' `reconciledAmt`
        divider.issue(address(cropsAdapter), newMaturity, (30 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (30 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);

        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (20 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (20 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), (30 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        assertClose(cropsAdapter.tBalance(bob), (20 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);
    }

    // Alice issues S1-YTs and S2-YTs before reconciling S1
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstIV(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // alice issues on S1
        divider.issue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (100 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (0 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);

        // alice issues on S2
        divider.issue(address(cropsAdapter), newMaturity, (100 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (200 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (0 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);

        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);

        // settle S1
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's position
        assertEq(cropsAdapter.tBalance(alice), (200 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(alice), 0);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        cropsAdapter.reconcile(users, maturities);

        assertEq(cropsAdapter.tBalance(alice), (100 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(alice), (100 * tBal) / 100);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        assertEq(cropsAdapter.tBalance(alice), (100 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertClose(cropsAdapter.tBalance(alice), (0 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(alice), (0 * tBal) / 100);
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionWithScaleChanges(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100); // 60%
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        // scale changes to 2e18
        is4626Target ? increaseScale(address(aTarget)) : cropsAdapter.setScale(2e18);
        assertEq(cropsAdapter.scale(), 2e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertClose(cropsAdapter.reconciledAmt(alice), 0);
        assertClose(cropsAdapter.reconciledAmt(bob), 0);

        // tBalance has changed since scale has changed as well
        assertClose(cropsAdapter.tBalance(alice), (30 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (20 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        cropsAdapter.reconcile(users, maturities);

        assertClose(cropsAdapter.tBalance(alice), 0);
        assertClose(cropsAdapter.tBalance(bob), 0);
        assertClose(cropsAdapter.reconciledAmt(alice), (30 * tBal) / 100);
        assertClose(cropsAdapter.reconciledAmt(bob), (20 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        divider.issue(address(cropsAdapter), newMaturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(bob), (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 60 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(alice), 120 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 80 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 120 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 80 * 1e18);

        // reconciled amounts should be 0 after combining
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(alice));
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertClose(cropsAdapter.reconciledAmt(alice), 0);

        hevm.startPrank(bob);
        divider.combine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(bob));
        divider.combine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(bob));
        hevm.stopPrank();
        assertClose(cropsAdapter.reconciledAmt(bob), 0);
    }

    function testFuzzDiluteRewardsIfNoReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(alice) > 0);
        assertTrue(cropsAdapter.tBalance(alice) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // Bob closes his YT position
        hevm.prank(bob);
        YT(yt).collect();
        assertEq(cropsAdapter.tBalance(bob), 0);
        assertEq(ERC20(yt).balanceOf(bob), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Alice has 30 reward2 tokens
        // - Bob has 20 reward tokens
        // - Bob has 20 reward2 tokens
        assertClose(ERC20(reward).balanceOf(address(cropsAdapter)), 0, 2);
        assertClose(ERC20(reward2).balanceOf(address(cropsAdapter)), 0, 2);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Bob issues some target and this should represent 100% of the rewards
        // but, as Alice is still holding some YTs, she will dilute Bob's rewards
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);
        hevm.prank(bob);
        YT(newYt).collect();

        // Bob should recive the 50 newly minted reward tokens
        // but that's not true because his rewards were diluted
        assertTrue(ERC20(reward).balanceOf(bob) != 70 * 1e18);
        assertTrue(ERC20(reward2).balanceOf(bob) != 70 * 1e18);
        // Bob only receives 20 reward tokens
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        // Alice can claim reward tokens with her old YTs
        // after that, their old YTs will be burnt
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertEq(cropsAdapter.tBalance(alice), 0);
        assertEq(ERC20(yt).balanceOf(alice), 0);

        // since Alice has called collect, her YTs should have been redeemed
        // and she won't be diluting anynmore
        assertEq(ERC20(yt).balanceOf(alice), 0);
    }

    function testFuzzDiluteRewardsIfLateReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        YT(yt).collect();
        hevm.prank(bob);
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(alice) > 0);
        assertTrue(cropsAdapter.tBalance(alice) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), maturity);

        // Bob closes his YT position and rewards
        hevm.prank(bob);
        YT(yt).collect();
        assertEq(cropsAdapter.tBalance(bob), 0);
        assertEq(ERC20(yt).balanceOf(bob), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Alice has 30 reward2 tokens
        // - Bob has 20 reward tokens
        // - Bob has 20 reward2 tokens
        assertClose(ERC20(reward).balanceOf(address(cropsAdapter)), 0, 2);
        assertClose(ERC20(reward2).balanceOf(address(cropsAdapter)), 0, 2);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Bob issues some target and this should represent 100% of the shares
        // but, as Alice is still holding some YTs from previous series, she will dilute Bob's rewards
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);
        hevm.prank(bob);
        YT(newYt).collect();

        // Bob should recieve the 50 newly minted reward tokens
        // but that's not true because his rewards have been diluted
        assertTrue(ERC20(reward).balanceOf(bob) != 70 * 1e18);
        assertTrue(ERC20(reward2).balanceOf(bob) != 70 * 1e18);
        // Bob only receives 20 reward tokens
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(bob), 40 * 1e18);

        // late reconcile Alice's position
        assertEq(cropsAdapter.reconciledAmt(alice), 0);
        assertEq(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = alice;
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(alice), 0);
        assertEq(cropsAdapter.reconciledAmt(alice), (60 * tBal) / 100);

        // rewards (with bonus) should have been distributed to Alice after reconciling
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);

        // after user collecting, YTs are burnt and and reconciled amount should go to 0
        YT(yt).collect();
        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(yt).balanceOf(alice), 0);
        assertEq(cropsAdapter.reconciledAmt(alice), 0);
    }

    /*              Jan                                                          Dec (maturity)
     *  Dec 2021 Series:  |-------------------------------|-------------------------------|
     *
     *                                              July (maturity)
     *  July 2022 Series: |-------------------------------|--------->
     *
     *                                                  ^ July series
     *                                                    reconcilation
     */
    function testFuzzReconcileSingleSeriesWhenTwoSeriesOverlap(uint256 tBal) public {
        assumeBounds(tBal);
        // current date is 1st Jan 2021 00:00 UTC
        hevm.warp(1609459200);

        // sponsor a 12 month maturity (December 1st 2021)
        uint256 maturity = getValidMaturity(2021, 12);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        // Alice issues on December Series
        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        assertEq(reward.balanceOf(alice), 0);
        assertEq(reward2.balanceOf(alice), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(block.timestamp + 12 weeks); // Current date is March

        // sponsor July Series
        uint256 newMaturity = getValidMaturity(2021, 7);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Alice issues 0 on July series and she gets rewards from the December Series
        divider.issue(address(cropsAdapter), newMaturity, 0);
        assertClose(reward.balanceOf(alice), 50 * 1e18);
        assertClose(reward2.balanceOf(alice), 50 * 1e18);

        // Bob issues on new series (no rewards are yet to be distributed to Bob)
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(reward.balanceOf(bob), 0);
        assertClose(reward2.balanceOf(bob), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // Moving to July Series maturity to be able to settle the series
        hevm.warp(newMaturity + 1 seconds);
        divider.settleSeries(address(cropsAdapter), newMaturity);

        // reconcile Alice's and Bob's positions
        assertEq(cropsAdapter.reconciledAmt(alice), 0);
        assertEq(cropsAdapter.reconciledAmt(bob), 0);
        assertEq(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(bob), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = newMaturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(alice), (60 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(bob), 0);
        assertEq(cropsAdapter.reconciledAmt(alice), 0);
        assertEq(cropsAdapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Both Alice and Bob should get their rewards
        assertClose(reward.balanceOf(alice), 50 * 1e18);
        assertClose(reward2.balanceOf(alice), 50 * 1e18);
        assertClose(reward.balanceOf(bob), 20 * 1e18);
        assertClose(reward2.balanceOf(bob), 20 * 1e18);

        // Alice should still be able to collect her rewards from
        // the December series (30 reward tokens)
        divider.issue(address(cropsAdapter), maturity, 0);
        assertClose(reward.balanceOf(alice), 80 * 1e18);
        assertClose(reward2.balanceOf(alice), 80 * 1e18);
    }

    // update rewards tokens tests

    function testAddRewardsTokens() public {
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));

        hevm.prank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory
        hevm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(rewardTokens);

        cropsAdapter.setRewardTokens(rewardTokens);

        assertEq(cropsAdapter.rewardTokens(0), address(reward));
        assertEq(cropsAdapter.rewardTokens(1), address(reward2));
        assertEq(cropsAdapter.rewardTokens(2), address(reward3));
    }

    function testRemoveRewardsTokens() public {
        address[] memory newRewardTokens = new address[](1);

        hevm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(newRewardTokens);

        hevm.prank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory
        cropsAdapter.setRewardTokens(newRewardTokens);

        assertEq(cropsAdapter.rewardTokens(0), address(0));
    }

    function testCantSetRewardsTokens() public {
        MockToken reward2 = new MockToken("Reward Token 2", "RT2", 18);
        rewardTokens.push(address(reward2));
        hevm.expectRevert("UNTRUSTED");
        cropsAdapter.setRewardTokens(rewardTokens);
    }

    // claimer tests

    function testCantSetClaimer(uint256 tBal) public {
        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x4b1d));
        cropsAdapter.setClaimer(address(cropsFactory));
    }

    function testCanSetClaimer(uint256 tBal) public {
        hevm.expectEmit(true, true, true, true);
        emit ClaimerChanged(address(1));

        hevm.prank(address(cropsFactory));
        cropsAdapter.setClaimer(address(1));
        assertEq(cropsAdapter.claimer(), address(1));
    }

    function testFuzzSimpleDistributionAndCollectWithClaimer(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        MockClaimer claimer = new MockClaimer(address(cropsAdapter), rewardTokens);
        hevm.prank(address(cropsFactory));
        cropsAdapter.setClaimer(address(claimer));

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        hevm.prank(bob);
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        uint256 tBalBefore = ERC20(cropsAdapter.target()).balanceOf(address(cropsAdapter));

        assertEq(reward.balanceOf(bob), 0);
        assertEq(reward2.balanceOf(bob), 0);

        hevm.prank(bob);
        YT(yt).collect();
        assertClose(reward.balanceOf(bob), 24 * 1e18);
        assertClose(reward2.balanceOf(bob), 24 * 1e6);
        uint256 tBalAfter = ERC20(cropsAdapter.target()).balanceOf(address(cropsAdapter));
        assertEq(tBalAfter, tBalBefore);
    }

    function testFuzzSimpleDistributionAndCollectWithClaimerReverts(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        MockClaimer claimer = new MockClaimer(address(cropsAdapter), rewardTokens);
        claimer.setTransfer(false); // make claimer not to return the target back to adapter

        hevm.prank(address(cropsFactory));
        cropsAdapter.setClaimer(address(claimer));

        divider.issue(address(cropsAdapter), maturity, (60 * tBal) / 100);

        hevm.prank(bob);
        hevm.expectRevert(abi.encodeWithSelector(Errors.BadContractInteration.selector));
        divider.issue(address(cropsAdapter), maturity, (40 * tBal) / 100);
    }

    // helpers

    function assumeBounds(uint256 tBal) internal {
        // adding bounds so we can use assertClose without such a high tolerance
        hevm.assume(tBal > 0.1 ether);
        hevm.assume(tBal < 1000 ether);
    }

    function assertClose(uint256 a, uint256 b) public override {
        assertClose(a, b, 1500);
    }

    /* ========== LOGS ========== */

    event Reconciled(address indexed usr, uint256 tBal, uint256 maturity);
    event ClaimerChanged(address indexed claimer);
    event Distributed(address indexed usr, address indexed token, uint256 amount);
    event RewardTokensChanged(address[] indexed rewardTokens);
    event RewardsClaimed(address indexed token, address indexed recipient, uint256 indexed amount);
}
