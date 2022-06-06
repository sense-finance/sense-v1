// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { BaseAdapter } from "../../adapters/BaseAdapter.sol";
import { Divider } from "../../Divider.sol";

import { MockCropsAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockCropsFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { TestHelper } from "../test-helpers/TestHelper.sol";

contract CropsAdapters is TestHelper {
    using FixedMath for uint256;

    MockToken internal reward2;
    MockCropsAdapter internal cropsAdapter;
    MockCropsFactory internal cropsFactory;
    MockTarget internal aTarget;

    // reward tokens
    address[] public rewardTokens;

    function setUp() public virtual override {
        super.setUp();
        reward2 = new MockToken("Reward Token 2", "RT2", 6);
        aTarget = new MockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals);
        rewardTokens = [address(reward), address(reward2)];
        cropsFactory = createCropsFactory(address(aTarget), rewardTokens);
        address f = periphery.deployAdapter(address(cropsFactory), address(aTarget), ""); // deploy & onboard target through Periphery
        cropsAdapter = MockCropsAdapter(f);
        divider.setGuard(address(cropsAdapter), 10 * 2**128);
        updateUser(alice, aTarget, stake, 2**128);
        updateUser(bob, aTarget, stake, 2**128);
        updateUser(jim, aTarget, stake, 2**128);
    }

    function testAdapterHasParams() public {
        MockToken underlying = new MockToken("Dai", "DAI", 18);
        MockTarget target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

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
            target.underlying(),
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
        assertEq(cropsAdapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(cropsAdapter.mode(), MODE);
    }

    // distribution tests

    function testFuzzDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 0 * 1e6);

        bob.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        bob.doIssue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);
    }

    function testFuzzSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 20 * 1e6);
    }

    function testFuzzProportionalDistribution() public {
        // assumeBounds(tBal);
        uint256 tBal = 100 * 1e18;
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 0 * 1e6);

        bob.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        bob.doIssue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (20 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e6);

        reward.mint(address(cropsAdapter), 30 * 1e18);
        reward2.mint(address(cropsAdapter), 30 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        bob.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 80 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 50 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
    }

    function testFuzzSimpleDistributionAndCollect(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);

        bob.doCollect(yt);
        assertClose(reward.balanceOf(address(bob)), 24 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 24 * 1e6);
    }

    function testFuzzDistributionCollectAndTransferMultiStep(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        // bob issues 40, now the pool is 40% bob and 60% alice
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(cropsAdapter), 100 * 1e18);
        reward2.mint(address(cropsAdapter), 100 * 1e6);

        // bob transfers all of his Yield to jim
        // now the pool is 70% jim and 30% alice
        bob.doTransfer(yt, address(jim), ERC20(yt).balanceOf(address(bob)));
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertClose(reward.balanceOf(address(bob)), 44 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 44 * 1e6);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertClose(reward.balanceOf(address(jim)), 50 * 1e18);
        assertClose(reward2.balanceOf(address(jim)), 50 * 1e6);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        alice.doCollect(yt);
        assertClose(reward.balanceOf(address(alice)), 66 * 1e18);
        assertClose(reward2.balanceOf(address(alice)), 66 * 1e6);

        // now if another airdop happens, jim should get shares proportional to his new yt balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(cropsAdapter), 100 * 1e18);
        reward2.mint(address(cropsAdapter), 100 * 1e6);
        jim.doCollect(yt);
        assertClose(reward.balanceOf(address(jim)), 120 * 1e18);
        assertClose(reward2.balanceOf(address(jim)), 120 * 1e6);
        alice.doCollect(yt);
        assertClose(reward.balanceOf(address(alice)), 96 * 1e18);
        assertClose(reward2.balanceOf(address(alice)), 96 * 1e6);
    }

    function testFuzzDistributionAddRewardToken(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        hevm.stopPrank();
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        // add new reward token
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));
        hevm.startPrank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0);

        alice.doIssue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);
        reward3.mint(address(cropsAdapter), 10 * 1e18);

        alice.doIssue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 20 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 10 * 1e18);
    }

    function testFuzzDistributionRemoveRewardToken(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        hevm.stopPrank();
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        // remove reward token
        rewardTokens.pop();
        hevm.startPrank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
    }

    function testFuzzCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint256 tBal) public {
        assumeBounds(tBal);
        tBal = uint128(fuzzWithBounds(tBal, 1000, type(uint32).max));
        cropsAdapter.setScale(1e18);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);

        alice.doIssue(address(cropsAdapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(cropsAdapter), airdrop);
        reward2.mint(address(cropsAdapter), airdrop);
        alice.doCollect(yt);
        assertTrue(cropsAdapter.tBalance(address(alice)) > 0);

        reward2.mint(address(cropsAdapter), airdrop);
        hevm.warp(maturity);
        alice.doSettleSeries(address(cropsAdapter), maturity);
        alice.doCollect(yt);

        assertEq(cropsAdapter.tBalance(address(alice)), 0);
        uint256 collected = alice.doCollect(yt); // try collecting after redemption
        assertEq(collected, 0);
    }

    // reconcile tests

    function testFuzzReconcileMoreThanOnce(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // reconcile Bob's position
        assertEq(cropsAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(bob);
        cropsAdapter.reconcile(users, maturities);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 20 * 1e18);
    }

    function testFuzzGetMaturedSeriesRewardsIfReconcileAfterMaturity(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // reconcile Bob's position
        assertEq(cropsAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(bob);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 20 * 1e18);
    }

    function testFuzzCantDiluteRewardsIfReconciledInSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(cropsAdapter), maturity, (100 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(cropsAdapter), 20 * 1e18);
        reward2.mint(address(cropsAdapter), 20 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's position
        assertEq(cropsAdapter.tBalance(address(alice)), (200 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(alice);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), (200 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(address(alice)), 0);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), newMaturity, (50 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);

        reward.mint(address(cropsAdapter), 30 * 1e18);
        reward2.mint(address(cropsAdapter), 30 * 1e18);

        alice.doIssue(address(cropsAdapter), newMaturity, (10 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 0);

        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e18);

        alice.doCollect(yt);
        bob.doIssue(address(cropsAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropsAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(address(alice)), 0);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        alice.doIssue(address(cropsAdapter), newMaturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 60 * 1e18);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        alice.doCombine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionWithScaleChanges(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e18);

        // scale changes
        hevm.warp(maturity / 2);
        cropsAdapter.setScale(2e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);

        // tBalance has changed since scale has changed as well
        assertClose(cropsAdapter.tBalance(address(alice)), (30 * tBal) / 100);
        assertClose(cropsAdapter.tBalance(address(bob)), (20 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropsAdapter.reconcile(users, maturities);
        assertClose(cropsAdapter.tBalance(address(alice)), 0);
        assertClose(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), (30 * tBal) / 100);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), (20 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 60 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        alice.doIssue(address(cropsAdapter), newMaturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 60 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropsAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 120 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 120 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 80 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 80 * 1e18);

        // reconciled amounts should be 0 after combining
        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        alice.doCombine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);

        bob.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(bob)));
        bob.doCombine(address(cropsAdapter), newMaturity, ERC20(newYt).balanceOf(address(bob)));
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);
    }

    function testFuzzDiluteRewardsIfNoReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(address(alice)) > 0);
        assertTrue(cropsAdapter.tBalance(address(alice)) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // Bob closes his YT position
        bob.doCollect(yt);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(ERC20(yt).balanceOf(address(bob)), 0);

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
        bob.doIssue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);
        bob.doCollect(newYt);

        // Bob should recive the 50 newly minted reward tokens
        // but that's not true because his rewards were diluted
        assertTrue(ERC20(reward).balanceOf(address(bob)) != 70 * 1e18);
        assertTrue(ERC20(reward2).balanceOf(address(bob)) != 70 * 1e18);
        // Bob only receives 20 reward tokens
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e18);

        // Alice can claim reward tokens with her old YTs
        // after that, their old YTs will be burnt
        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
        assertEq(cropsAdapter.tBalance(address(alice)), 0);
        assertEq(ERC20(yt).balanceOf(address(alice)), 0);

        // since Alice has called collect, her YTs should have been redeemed
        // and she won't be diluting anynmore
        assertEq(ERC20(yt).balanceOf(address(alice)), 0);
    }

    function testFuzzDiluteRewardsIfLateReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        bob.doIssue(address(cropsAdapter), maturity, (40 * tBal) / 100);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(address(alice)) > 0);
        assertTrue(cropsAdapter.tBalance(address(alice)) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), maturity);

        // Bob closes his YT position and rewards
        bob.doCollect(yt);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(ERC20(yt).balanceOf(address(bob)), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Alice has 30 reward2 tokens
        // - Bob has 20 reward tokens
        // - Bob has 20 reward2 tokens
        assertClose(ERC20(reward).balanceOf(address(cropsAdapter)), 0, 2);
        assertClose(ERC20(reward2).balanceOf(address(cropsAdapter)), 0, 2);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);
        hevm.stopPrank();

        // Bob issues some target and this should represent 100% of the shares
        // but, as Alice is still holding some YTs from previous series, she will dilute Bob's rewards
        bob.doIssue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);
        bob.doCollect(newYt);

        // Bob should recieve the 50 newly minted reward tokens
        // but that's not true because his rewards have been diluted
        assertTrue(ERC20(reward).balanceOf(address(bob)) != 70 * 1e18);
        assertTrue(ERC20(reward2).balanceOf(address(bob)) != 70 * 1e18);
        // Bob only receives 20 reward tokens
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e18);

        // late reconcile Alice's position
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropsAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(alice);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);

        // rewards (with bonus) should have been distributed to Alice after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);

        // after user collecting, YTs are burnt and and reconciled amount should go to 0
        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(yt).balanceOf(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
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
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        // Alice issues on December Series
        alice.doIssue(address(cropsAdapter), maturity, (60 * tBal) / 100);
        assertEq(reward.balanceOf(address(alice)), 0);
        assertEq(reward2.balanceOf(address(alice)), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        hevm.warp(block.timestamp + 12 weeks); // Current date is March

        // sponsor July Series
        uint256 newMaturity = getValidMaturity(2021, 7);
        (, address newYt) = periphery.sponsorSeries(address(cropsAdapter), newMaturity, true);

        // Alice issues 0 on July series and she gets rewards from the December Series
        alice.doIssue(address(cropsAdapter), newMaturity, 0);
        assertClose(reward.balanceOf(address(alice)), 50 * 1e18);
        assertClose(reward2.balanceOf(address(alice)), 50 * 1e18);

        // Bob issues on new series (no rewards are yet to be distributed to Bob)
        bob.doIssue(address(cropsAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(reward.balanceOf(address(bob)), 0);
        assertClose(reward2.balanceOf(address(bob)), 0);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e18);

        // Moving to July Series maturity to be able to settle the series
        hevm.warp(newMaturity + 1 seconds);
        alice.doSettleSeries(address(cropsAdapter), newMaturity);

        // reconcile Alice's and Bob's positions
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropsAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = newMaturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropsAdapter.reconcile(users, maturities);
        assertEq(cropsAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropsAdapter.tBalance(address(bob)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropsAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Both Alice and Bob should get their rewards
        assertClose(reward.balanceOf(address(alice)), 50 * 1e18);
        assertClose(reward2.balanceOf(address(alice)), 50 * 1e18);
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 20 * 1e18);

        // Alice should still be able to collect her rewards from
        // the December series (30 reward tokens)
        alice.doIssue(address(cropsAdapter), maturity, 0);
        assertClose(reward.balanceOf(address(alice)), 80 * 1e18);
        assertClose(reward2.balanceOf(address(alice)), 80 * 1e18);
    }

    // update rewards tokens tests

    event RewardTokensChanged(address[] indexed rewardTokens);

    function testAddRewardsTokens() public {
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));

        hevm.startPrank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory
        hevm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(rewardTokens);

        cropsAdapter.setRewardTokens(rewardTokens);

        assertEq(cropsAdapter.rewardTokens(0), address(reward));
        assertEq(cropsAdapter.rewardTokens(1), address(reward2));
        assertEq(cropsAdapter.rewardTokens(2), address(reward3));
    }

    function testRemoveRewardsTokens() public {
        address[] memory newRewardTokens = new address[](1);
        hevm.startPrank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory

        hevm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(newRewardTokens);

        cropsAdapter.setRewardTokens(newRewardTokens);

        assertEq(cropsAdapter.rewardTokens(0), address(0));
    }

    function testCantSetRewardsTokens() public {
        MockToken reward2 = new MockToken("Reward Token 2", "RT2", 18);
        rewardTokens.push(address(reward2));
        hevm.expectRevert("UNTRUSTED");
        cropsAdapter.setRewardTokens(rewardTokens);
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
}
