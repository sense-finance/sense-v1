// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626CropAdapter } from "../../adapters/abstract/erc4626/ERC4626CropAdapter.sol";
import { PingPongClaimer } from "../../adapters/implementations/claimers/PingPongClaimer.sol";
import { Divider } from "../../Divider.sol";
import { Periphery } from "../../Periphery.sol";
import { YT } from "../../tokens/YT.sol";

import { MockCropAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { MockClaimer } from "../test-helpers/mocks/MockClaimer.sol";
import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

contract CropAdapters is TestHelper {
    using FixedMath for uint256;

    function setUp() public virtual override {
        ISSUANCE_FEE = 0; // super.setUp will create an adapter with 0 fee to simplify tests math
        MAX_MATURITY = 52 weeks; // super.setUp will create an adapter with 12 month max maturity

        super.setUp();

        // freeze scale to 1e18 (only for non 4626 targets)
        if (!is4626Target) adapter.setScale(1e18);

        // set guarded to false to avoid reverts by issuing more than guard when fuzzing
        divider.setGuarded(false);
    }

    function testAdapterHasParams() public {
        MockToken underlying = new MockToken("Dai", "DAI", uDecimals);
        MockTargetLike target = MockTargetLike(
            deployMockTarget(address(underlying), "Compound Dai", "cDAI", tDecimals)
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

        MockCropAdapter cropAdapter = new MockCropAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams,
            address(reward)
        );
        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = adapter.adapterParams();
        assertEq(cropAdapter.reward(), address(reward));
        assertEq(cropAdapter.name(), "Compound Dai Adapter");
        assertEq(cropAdapter.symbol(), "cDAI-adapter");
        assertEq(cropAdapter.target(), address(target));
        assertEq(cropAdapter.underlying(), address(underlying));
        assertEq(cropAdapter.divider(), address(divider));
        assertEq(cropAdapter.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(cropAdapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(cropAdapter.mode(), MODE);

        // sanity check trusted addresses
        assertTrue(cropAdapter.isTrusted(address(divider)));
        assertTrue(cropAdapter.isTrusted(address(this)));
    }

    function testExtractToken() public {
        // can extract someReward
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        someReward.mint(address(adapter), 1e18);
        assertEq(someReward.balanceOf(address(adapter)), 1e18);

        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(someReward), Constants.REWARDS_RECIPIENT, 1e18);

        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 0);
        // anyone can call extract token
        vm.prank(address(0xfede));
        adapter.extractToken(address(someReward));
        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 1e18);

        (address target, address stake, ) = adapter.getStakeAndTarget();

        // can NOT extract stake
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        adapter.extractToken(address(stake));

        // can NOT extract target
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        adapter.extractToken(address(target));

        // can NOT extract reward
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        adapter.extractToken(address(reward));
    }

    // distribution tests

    function testFuzzDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), maturity, true, data, _getQuote(address(stake), address(stake)));

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        vm.expectEmit(true, true, true, false);
        emit Distributed(alice, address(reward), 0);

        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 0);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 0);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);
    }

    function testFuzzSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (100 * tBal) / 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(adapter), 10 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        divider.issue(address(adapter), maturity, (100 * tBal) / 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        divider.issue(address(adapter), maturity, (100 * tBal) / 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        reward.mint(address(adapter), 10 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 10 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 20 * 10**rDecimals);
    }

    function testFuzzProportionalDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 0);

        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 0);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        divider.issue(address(adapter), maturity, (20 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        reward.mint(address(adapter), 30 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 0);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 80 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 50 * 10**rDecimals);

        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
    }

    function testFuzzSimpleDistributionAndCollect(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(bob), 0);

        reward.mint(address(adapter), 60 * 10**rDecimals);

        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(reward.balanceOf(bob), 24 * 10**rDecimals);
    }

    function testFuzzDistributionCollectAndTransferMultiStep(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);
        // bob issues 40, now the pool is 40% bob and 60% alice
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(bob), 0);

        // 60 reward tokens are airdropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(adapter), 60 * 10**rDecimals);
        vm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        vm.prank(jim);
        divider.issue(address(adapter), maturity, (100 * tBal) / 100);

        vm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 * 10**rDecimals should go to bob, 30 to alice, and 50 * 10**rDecimals to jim
        reward.mint(address(adapter), 100 * 10**rDecimals);

        // bob transfers all of his Yield to jim
        // now the pool is 70% jim and 30% alice
        uint256 bytBal = ERC20(yt).balanceOf(bob);
        vm.prank(bob);
        MockToken(yt).transfer(jim, bytBal);
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertApproxRewardBal(reward.balanceOf(bob), 44 * 10**rDecimals);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertApproxRewardBal(reward.balanceOf(jim), 50 * 10**rDecimals);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        YT(yt).collect();
        assertApproxRewardBal(reward.balanceOf(alice), 66 * 10**rDecimals);

        // now if another airdop happens, jim should get shares proportional to his new yt balance
        vm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(adapter), 100 * 10**rDecimals);
        vm.prank(jim);
        YT(yt).collect();
        assertApproxRewardBal(reward.balanceOf(jim), 120 * 10**rDecimals);
        YT(yt).collect();
        assertApproxRewardBal(reward.balanceOf(alice), 96 * 10**rDecimals);
    }

    function testFuzzCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(adapter), airdrop);
        YT(yt).collect();
        assertTrue(adapter.tBalance(alice) > 0);

        reward.mint(address(adapter), airdrop);
        vm.warp(maturity);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);
        YT(yt).collect();

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        uint256 collected = YT(yt).collect(); // try collecting after redemption
        assertEq(collected, 0);
    }

    // reconcile tests

    function testFuzzReconcileMoreThanOnce(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(bob), 0);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Bob's position
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = bob;

        vm.expectEmit(true, false, false, false);
        emit Reconciled(bob, 0, maturity);

        adapter.reconcile(users, maturities);
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertApproxRewardBal(reward.balanceOf(bob), 20 * 10**rDecimals);
    }

    function testFuzzGetMaturedSeriesRewardsIfReconcileAfterMaturity(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(bob), 0);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Bob's position
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = bob;
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertApproxRewardBal(reward.balanceOf(bob), 20 * 10**rDecimals);
    }

    function testFuzzCantDiluteRewardsIfReconciledInSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(adapter), 10 * 10**rDecimals);

        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        divider.issue(address(adapter), maturity, 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        reward.mint(address(adapter), 20 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's position
        assertApproxRewardBal(adapter.tBalance(alice), 200);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = alice;
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 200);
        assertApproxRewardBal(adapter.tBalance(alice), 0);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        periphery.sponsorSeries(address(adapter), newMaturity, true, data, _getQuote(address(stake), address(stake)));

        divider.issue(address(adapter), newMaturity, 50 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);

        reward.mint(address(adapter), 30 * 10**rDecimals);

        divider.issue(address(adapter), newMaturity, 10);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);

        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
    }

    // On the 2nd Series we issue an amount which is equal to the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstI(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's & Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Issue an amount equal to the users' `reconciledAmt`
        divider.issue(address(adapter), newMaturity, (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);

        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        vm.prank(bob);
        YT(yt).collect();
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs first and her tBalance should decrement
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
    }

    // On the 2nd Series we issue an amount which is bigger than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's & Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Issue an amount bigger than the users' `reconciledAmt`
        divider.issue(address(adapter), newMaturity, (120 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (120 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);

        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (80 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (80 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(newYt).collect();
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), (120 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        assertApproxRewardBal(adapter.tBalance(bob), (80 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);
    }

    // On the 2nd Series we issue an amount which is smaller than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstIII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's & Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Issue an amount bigger than the users' `reconciledAmt`
        divider.issue(address(adapter), newMaturity, (30 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (30 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);

        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (20 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (20 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), (30 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        assertApproxRewardBal(adapter.tBalance(bob), (20 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);
    }

    // Alice issues S1-YTs and S2-YTs before reconciling S1
    function testFuzzCantDiluteRewardsIfReconciledAndCombineS1_YTsFirstIV(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // alice issues on S1
        divider.issue(address(adapter), maturity, (100 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (100 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (0 * tBal) / 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 0);

        // alice issues on S2
        divider.issue(address(adapter), newMaturity, (100 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (200 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (0 * tBal) / 100);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 0);

        reward.mint(address(adapter), 10 * 10**rDecimals);

        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 10 * 10**rDecimals);

        // settle S1
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's position
        assertEq(adapter.tBalance(alice), (200 * tBal) / 100);
        assertEq(adapter.reconciledAmt(alice), 0);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        adapter.reconcile(users, maturities);

        assertEq(adapter.tBalance(alice), (100 * tBal) / 100);
        assertEq(adapter.reconciledAmt(alice), (100 * tBal) / 100);

        // Alice combines her S1-YTs first so her tBalance should NOT decrement
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertEq(adapter.tBalance(alice), (100 * tBal) / 100);
        assertEq(adapter.reconciledAmt(alice), 0);

        // Alice combines her S2-YTs and her tBalance should decrement
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.tBalance(alice), (0 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (0 * tBal) / 100);
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionWithScaleChanges(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        // scale changes to 2e18
        is4626Target ? increaseScale(address(target)) : adapter.setScale(2e18);
        assertEq(adapter.scale(), 2e18);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's & Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);

        // tBalance has changed since scale has changed as well
        assertApproxRewardBal(adapter.tBalance(alice), (30 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (20 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (30 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (20 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), newMaturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 120 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 80 * 10**rDecimals);

        // reconciled amounts should be 0 after combining
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        vm.startPrank(bob);
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(bob));
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(bob));
        vm.stopPrank();
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
    }

    function testFuzzCantDiluteRewardsInProportionalDistributionWithScaleChangesAndCollectAfterReconcile(uint256 tBal)
        public
    {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // scale changes to 2e18
        is4626Target ? increaseScale(address(target)) : adapter.setScale(2e18);
        assertEq(adapter.scale(), 2e18);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        assertEq(ERC20(reward).balanceOf(alice), 0);
        assertEq(ERC20(reward).balanceOf(bob), 0);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // reconcile Alice's & Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.totalTarget(), 0);

        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), newMaturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);

        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 90 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 60 * 10**rDecimals);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 120 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 80 * 10**rDecimals);

        // reconciled amounts should be 0 after combining
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(alice));
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);

        vm.startPrank(bob);
        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(bob));
        divider.combine(address(adapter), newMaturity, ERC20(newYt).balanceOf(bob));
        vm.stopPrank();
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
    }

    function testFuzzDiluteRewardsIfNoReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(alice) > 0);
        assertTrue(adapter.tBalance(alice) > 0);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // Bob closes his YT position
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertEq(ERC20(yt).balanceOf(bob), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Bob has 20 * 10**rDecimals reward tokens
        assertApproxRewardBal(ERC20(reward).balanceOf(address(adapter)), 0);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Bob issues some target and this should represent 100% of the rewards
        // but, as Alice is still holding some YTs, she will dilute Bob's rewards
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(adapter), 50 * 10**rDecimals);
        vm.prank(bob);
        YT(newYt).collect();

        // Bob should recive the 50 * 10**rDecimals newly minted reward tokens
        // but that's not true because his rewards were diluted
        assertTrue(ERC20(reward).balanceOf(bob) != 70 * 10**rDecimals);
        // Bob only receives 20 * 10**rDecimals reward tokens
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        // Alice can claim reward tokens with her old YTs
        // after that, their old YTs will be burnt
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertEq(ERC20(yt).balanceOf(alice), 0);

        // since Alice has called collect, her YTs should have been redeemed
        // and she won't be diluting anynmore
        assertEq(ERC20(yt).balanceOf(alice), 0);
    }

    function testFuzzDiluteRewardsIfLateReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(adapter), 50 * 10**rDecimals);

        YT(yt).collect();
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 30 * 10**rDecimals);
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 20 * 10**rDecimals);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(alice) > 0);
        assertTrue(adapter.tBalance(alice) > 0);

        // settle series
        vm.warp(maturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), maturity);

        // Bob closes his YT position and rewards
        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertEq(ERC20(yt).balanceOf(bob), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Bob has 20 reward tokens
        assertApproxRewardBal(ERC20(reward).balanceOf(address(adapter)), 0);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Bob issues some target and this should represent 100% of the shares
        // but, as Alice is still holding some YTs from previous series, she will dilute Bob's rewards
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(adapter), 50 * 10**rDecimals);
        vm.prank(bob);
        YT(newYt).collect();

        // Bob should recieve the 50 newly minted reward tokens
        // but that's not true because his rewards have been diluted
        assertTrue(ERC20(reward).balanceOf(bob) != 70 * 10**rDecimals);
        // Bob only receives 20 reward tokens
        assertApproxRewardBal(ERC20(reward).balanceOf(bob), 40 * 10**rDecimals);

        // late reconcile Alice's position
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = alice;
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.tBalance(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), (60 * tBal) / 100);

        // rewards (with bonus) should have been distributed to Alice after reconciling
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);

        // after user collecting, YTs are burnt and and reconciled amount should go to 0
        YT(yt).collect();
        assertApproxRewardBal(ERC20(reward).balanceOf(alice), 60 * 10**rDecimals);
        assertApproxRewardBal(ERC20(yt).balanceOf(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
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
        vm.warp(1609459200);

        // sponsor a 12 month maturity (December 1st 2021)
        uint256 maturity = getValidMaturity(2021, 12);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Alice issues on December Series
        divider.issue(address(adapter), maturity, (60 * tBal) / 100); // 60%
        assertEq(reward.balanceOf(alice), 0);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        vm.warp(block.timestamp + 12 weeks); // Current date is March

        // sponsor July Series
        uint256 newMaturity = getValidMaturity(2021, 7);
        data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address newYt) = periphery.sponsorSeries(
            address(adapter),
            newMaturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        // Alice issues 0 on July series and she gets rewards from the December Series
        divider.issue(address(adapter), newMaturity, 0);
        assertApproxRewardBal(reward.balanceOf(alice), 50 * 10**rDecimals);

        // Bob issues on new series (no rewards are yet to be distributed to Bob)
        vm.prank(bob);
        divider.issue(address(adapter), newMaturity, (40 * tBal) / 100);
        assertApproxRewardBal(reward.balanceOf(bob), 0);

        reward.mint(address(adapter), 50 * 10**rDecimals);

        // Moving to July Series maturity to be able to settle the series
        vm.warp(newMaturity + 1 seconds);
        vm.prank(bob);
        divider.settleSeries(address(adapter), newMaturity);

        // reconcile Alice's and Bob's positions
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), 0);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = newMaturity;
        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;
        adapter.reconcile(users, maturities);
        assertApproxRewardBal(adapter.tBalance(alice), (60 * tBal) / 100);
        assertApproxRewardBal(adapter.tBalance(bob), 0);
        assertApproxRewardBal(adapter.reconciledAmt(alice), 0);
        assertApproxRewardBal(adapter.reconciledAmt(bob), (40 * tBal) / 100);

        // Both Alice and Bob should get their rewards
        assertApproxRewardBal(reward.balanceOf(alice), 50 * 10**rDecimals);
        assertApproxRewardBal(reward.balanceOf(bob), 20 * 10**rDecimals);

        // Alice should still be able to collect her rewards from
        // the December series (30 reward tokens)
        divider.issue(address(adapter), maturity, 0);
        assertApproxRewardBal(reward.balanceOf(alice), 80 * 10**rDecimals);
    }

    // update reward token tests

    function test4626SetRewardsTokens() public {
        if (!is4626Target) return;
        ERC4626CropAdapter a = ERC4626CropAdapter(address(adapter));

        vm.expectEmit(true, false, false, true);
        emit RewardTokenChanged(address(0xfede));

        vm.prank(address(factory)); // only factory can call `setRewardToken` as it was deployed via cropsFactory
        a.setRewardToken(address(0xfede));
        assertEq(a.reward(), address(0xfede));
    }

    function testSetRewardsTokens() public {
        if (is4626Target) return;
        vm.expectEmit(true, false, false, true);
        emit RewardTokenChanged(address(0xfede));

        vm.prank(address(factory)); // only factory can call `setRewardToken` as it was deployed via cropsFactory
        adapter.setRewardToken(address(0xfede));
        assertEq(adapter.reward(), address(0xfede));
    }

    function testCantSetRewardTokens() public {
        if (is4626Target) return;
        vm.expectRevert("UNTRUSTED");
        adapter.setRewardToken(address(0xfede));
    }

    function test4626CantSetRewardTokens() public {
        if (!is4626Target) return;
        vm.expectRevert("UNTRUSTED");
        ERC4626CropAdapter a = ERC4626CropAdapter(address(adapter));
        a.setRewardToken(address(0xfede));
    }

    // claimer tests

    function testCantSetClaimer() public {
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x4b1d));
        adapter.setClaimer(address(0x4b1d));
    }

    function testCanSetClaimer() public {
        vm.expectEmit(true, true, true, true);
        emit ClaimerChanged(address(1));

        // Can be changed by factory
        vm.prank(address(factory));
        adapter.setClaimer(address(1));
        assertEq(adapter.claimer(), address(1));

        // Can be changed by admin
        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setClaimer(address(2));
        assertEq(adapter.claimer(), address(2));
    }

    function testFuzzSimpleDistributionAndCollectWithClaimer(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        MockClaimer claimer = new MockClaimer(address(adapter), rewardTokens);
        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setClaimer(address(claimer));

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);
        vm.prank(bob);
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);

        uint256 tBalBefore = ERC20(adapter.target()).balanceOf(address(adapter));

        assertEq(reward.balanceOf(bob), 0);

        vm.prank(bob);
        YT(yt).collect();
        assertApproxRewardBal(reward.balanceOf(bob), 24 * 10**rDecimals);
        uint256 tBalAfter = ERC20(adapter.target()).balanceOf(address(adapter));
        assertEq(tBalAfter, tBalBefore);
    }

    function testFuzzSimpleDistributionAndCollectWithClaimerReverts(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);
        MockClaimer claimer = new MockClaimer(address(adapter), rewardTokens);
        claimer.setTransfer(false); // make claimer not to return the target back to adapter

        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setClaimer(address(claimer));

        divider.issue(address(adapter), maturity, (60 * tBal) / 100);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Errors.BadContractInteration.selector));
        divider.issue(address(adapter), maturity, (40 * tBal) / 100);
    }

    function testPingPongClaimer() public {
        uint256 tBal = 100e18;
        uint256 maturity = getValidMaturity(2021, 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (, address yt) = periphery.sponsorSeries(
            address(adapter),
            maturity,
            true,
            data,
            _getQuote(address(stake), address(stake))
        );

        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(reward);

        PingPongClaimer claimer = new PingPongClaimer();
        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setClaimer(address(claimer));

        divider.issue(address(adapter), maturity, tBal);

        // assert the ping pong claimer emits a transfer event
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(claimer), address(adapter), tBal);

        // calling issue does not revert
        divider.issue(address(adapter), maturity, tBal);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    // helpers

    function assumeBounds(uint256 tBal) internal {
        // adding bounds so we can use assertClose without such a high tolerance
        vm.assume(tBal > (10**(tDecimals - 1))); // 0.1 in target decimals
        // tBal is usually used for issuing, so we would we assume a max of 3 issue() calls per test case
        // and we know user's balance is MAX_TARGET
        vm.assume(tBal < MAX_TARGET / 3);
    }

    function assertApproxRewardBal(uint256 a, uint256 b) public {
        assertApproxEqAbs(a, b, 1500);
    }

    /* ========== LOGS ========== */

    event Reconciled(address indexed usr, uint256 tBal, uint256 maturity);
    event ClaimerChanged(address indexed claimer);
    event Distributed(address indexed usr, address indexed token, uint256 amount);
    event RewardTokenChanged(address indexed reward);
    event RewardTokensChanged(address[] indexed rewardTokens);
    event RewardsClaimed(address indexed token, address indexed recipient, uint256 indexed amount);
}
