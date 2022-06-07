// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { BaseAdapter } from "../../adapters/BaseAdapter.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";
import { Divider } from "../../Divider.sol";

import { MockAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { TestHelper } from "../test-helpers/TestHelper.sol";

contract CropAdapters is TestHelper {
    using FixedMath for uint256;

    MockAdapter internal cropAdapter;
    MockFactory internal cropFactory;
    MockTarget internal aTarget;

    function setUp() public virtual override {
        super.setUp();

        aTarget = new MockTarget(address(underlying), "Compound Dai", "cDAI", mockTargetDecimals);

        // create factory with 0 fee and 12 month maturity to simplify calculations
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: 0,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: 48 weeks,
            mode: MODE,
            tilt: 0
        });
        cropFactory = createFactory(address(aTarget), address(reward), factoryParams);
        address f = periphery.deployAdapter(address(cropFactory), address(aTarget), "");
        cropAdapter = MockAdapter(f);
        divider.setGuard(address(cropAdapter), 10 * 2**128);
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

        MockAdapter cropAdapter = new MockAdapter(
            address(divider),
            address(target),
            target.underlying(),
            ISSUANCE_FEE,
            adapterParams,
            address(reward)
        );
        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = cropAdapter
            .adapterParams();
        assertEq(cropAdapter.reward(), address(reward));
        assertEq(cropAdapter.name(), "Compound Dai Adapter");
        assertEq(cropAdapter.symbol(), "cDAI-adapter");
        assertEq(cropAdapter.target(), address(target));
        assertEq(cropAdapter.underlying(), address(underlying));
        assertEq(cropAdapter.divider(), address(divider));
        assertEq(cropAdapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(cropAdapter.mode(), MODE);
    }

    // distribution tests

    function testFuzzDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
    }

    function testFuzzSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);

        reward.mint(address(cropAdapter), 10 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(cropAdapter), 10 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 10);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
    }

    function testFuzzProportionalDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, (20 * tBal) / 100);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropAdapter), 30 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 0);
        bob.doIssue(address(cropAdapter), maturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);

        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
    }

    function testFuzzSimpleDistributionAndCollect(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(address(bob)), 0);

        reward.mint(address(cropAdapter), 60 * 1e18);

        bob.doCollect(yt);
        assertClose(reward.balanceOf(address(bob)), 24 * 1e18);
    }

    function testFuzzDistributionCollectAndTransferMultiStep(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        // bob issues 40, now the pool is 40% bob and 60% alice
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(address(bob)), 0);

        // 60 reward tokens are airdropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(cropAdapter), 60 * 1e18);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(cropAdapter), maturity, (100 * tBal) / 100);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 * 1e18 should go to bob, 30 to alice, and 50 * 1e18 to jim
        reward.mint(address(cropAdapter), 100 * 1e18);

        // bob transfers all of his Yield to jim
        // now the pool is 70% jim and 30% alice
        bob.doTransfer(yt, address(jim), ERC20(yt).balanceOf(address(bob)));
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertClose(reward.balanceOf(address(bob)), 44 * 1e18);

        // jim should have those 50 * 1e18 from the second airdrop (collected automatically when bob transferred to him)
        assertClose(reward.balanceOf(address(jim)), 50 * 1e18);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        alice.doCollect(yt);
        assertClose(reward.balanceOf(address(alice)), 66 * 1e18);

        // now if another airdop happens, jim should get shares proportional to his new yt balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(cropAdapter), 100 * 1e18);
        jim.doCollect(yt);
        assertClose(reward.balanceOf(address(jim)), 120 * 1e18);
        alice.doCollect(yt);
        assertClose(reward.balanceOf(address(alice)), 96 * 1e18);
    }

    function testFuzzCollectRewardSettleSeriesAndCheckTBalanceIsZero(uint256 tBal) public {
        assumeBounds(tBal);
        cropAdapter.setScale(1e18);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);

        alice.doIssue(address(cropAdapter), maturity, tBal);

        uint256 airdrop = 1e18;
        reward.mint(address(cropAdapter), airdrop);
        alice.doCollect(yt);
        assertTrue(cropAdapter.tBalance(address(alice)) > 0);

        reward.mint(address(cropAdapter), airdrop);
        hevm.warp(maturity);
        alice.doSettleSeries(address(cropAdapter), maturity);
        alice.doCollect(yt);

        assertEq(cropAdapter.tBalance(address(alice)), 0);
        uint256 collected = alice.doCollect(yt); // try collecting after redemption
        assertEq(collected, 0);
    }

    // reconcile tests

    function testFuzzReconcileMoreThanOnce(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(address(bob)), 0);

        reward.mint(address(cropAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Bob's position
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(bob);
        cropAdapter.reconcile(users, maturities);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);
    }

    function testFuzzGetMaturedSeriesRewardsIfReconcileAfterMaturity(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        assertEq(reward.balanceOf(address(bob)), 0);

        reward.mint(address(cropAdapter), 50 * 1e18);

        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Bob's position
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Bob received his rewards when reconciliation took place
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);
    }

    function testFuzzCantDiluteRewardsIfReconciledInSingleDistribution(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0);

        reward.mint(address(cropAdapter), 10 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(cropAdapter), maturity, 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(cropAdapter), 20 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's position
        assertEq(cropAdapter.tBalance(address(alice)), 200);
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(alice);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.reconciledAmt(address(alice)), 200);
        assertEq(cropAdapter.tBalance(address(alice)), 0);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), newMaturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);

        reward.mint(address(cropAdapter), 30 * 1e18);

        alice.doIssue(address(cropAdapter), newMaturity, 10);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);

        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
    }

    // on the 2nd Series we issue an amount which is equal to the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionI(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doCollect(yt);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // Issue an amount equal to the users' `reconciledAmt`
        alice.doIssue(address(cropAdapter), newMaturity, (60 * tBal) / 100);
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
    }

    // on the 2nd Series we issue an amount which is bigger than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doCollect(yt);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // Issue an amount bigger than the users' `reconciledAmt`
        alice.doIssue(address(cropAdapter), newMaturity, (120 * tBal) / 100);
        bob.doIssue(address(cropAdapter), newMaturity, (80 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
    }

    // on the 2nd Series we issue an amount which is smaller than the user's `reconciledAmt`
    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionIII(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doCollect(yt);
        bob.doIssue(address(cropAdapter), maturity, 0);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // Issue an amount bigger than the users' `reconciledAmt`
        alice.doIssue(address(cropAdapter), newMaturity, (30 * tBal) / 100);
        bob.doIssue(address(cropAdapter), newMaturity, (20 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(cropAdapter.reconciledAmt(address(alice)), 0);
        assertClose(cropAdapter.reconciledAmt(address(bob)), (20 * tBal) / 100);
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionIV(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 50 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's position
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        cropAdapter.reconcile(users, maturities);

        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 100 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // alice issues on new Series
        alice.doIssue(address(cropAdapter), newMaturity, (60 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(alice)), 100 * 1e18);

        // alice combines on new Series
        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), 0);

        // bob issues on new Series
        bob.doIssue(address(cropAdapter), newMaturity, (60 * tBal) / 100);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // Bob should receive 100% of rewards
        bob.doCollect(newYt);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);

        // Alice should not receive any rewards
        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 100 * 1e18);
    }

    function testFuzzCantDiluteRewardsIfReconciledInProportionalDistributionWithScaleChanges(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        // scale changes
        hevm.warp(maturity / 2);
        cropAdapter.setScale(2e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);

        // tBalance has changed since scale has changed as well
        assertClose(cropAdapter.tBalance(address(alice)), (30 * tBal) / 100);
        assertClose(cropAdapter.tBalance(address(bob)), (20 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertClose(cropAdapter.tBalance(address(alice)), 0);
        assertClose(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (30 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (20 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), newMaturity, (60 * tBal) / 100);
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertClose(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 120 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 80 * 1e18);

        // reconciled amounts should be 0 after combining
        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);

        bob.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(bob)));
        bob.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(bob)));
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
    }

    function testFuzzCantDiluteRewardsInProportionalDistributionWithScaleChangesAndCollectAfterReconcile(uint256 tBal)
        public
    {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        // scale changes
        hevm.warp(maturity / 2);
        cropAdapter.setScale(2e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        assertEq(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);
        assertEq(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // reconcile Alice's & Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        assertClose(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertClose(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);

        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertClose(cropAdapter.totalTarget(), 0);

        assertClose(cropAdapter.tBalance(address(alice)), 0);
        assertClose(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // rewards should have been distributed after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), newMaturity, (60 * tBal) / 100);
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);

        assertClose(ERC20(reward).balanceOf(address(alice)), 90 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 60 * 1e18);

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(newYt);
        bob.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(ERC20(reward).balanceOf(address(alice)), 120 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 80 * 1e18);

        // reconciled amounts should be 0 after combining
        alice.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        alice.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(alice)));
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);

        bob.doCombine(address(cropAdapter), maturity, ERC20(yt).balanceOf(address(bob)));
        bob.doCombine(address(cropAdapter), newMaturity, ERC20(newYt).balanceOf(address(bob)));
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
    }

    function testFuzzDiluteRewardsIfNoReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(address(alice)) > 0);
        assertTrue(cropAdapter.tBalance(address(alice)) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // Bob closes his YT position
        bob.doCollect(yt);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(ERC20(yt).balanceOf(address(bob)), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Bob has 20 * 1e18 reward tokens
        assertClose(ERC20(reward).balanceOf(address(cropAdapter)), 0);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();
        hevm.stopPrank();

        // Bob issues some target and this should represent 100% of the rewards
        // but, as Alice is still holding some YTs, she will dilute Bob's rewards
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropAdapter), 50 * 1e18);
        bob.doCollect(newYt);

        // Bob should recive the 50 * 1e18 newly minted reward tokens
        // but that's not true because his rewards were diluted
        assertTrue(ERC20(reward).balanceOf(address(bob)) != 70 * 1e18);
        // Bob only receives 20 * 1e18 reward tokens
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        // Alice can claim reward tokens with her old YTs
        // after that, their old YTs will be burnt
        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(ERC20(yt).balanceOf(address(alice)), 0);

        // since Alice has called collect, her YTs should have been redeemed
        // and she won't be diluting anynmore
        assertEq(ERC20(yt).balanceOf(address(alice)), 0);
    }

    function testFuzzDiluteRewardsIfLateReconcile(uint256 tBal) public {
        assumeBounds(tBal);
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        bob.doIssue(address(cropAdapter), maturity, (40 * tBal) / 100); // 40%

        reward.mint(address(cropAdapter), 50 * 1e18);

        alice.doCollect(yt);
        bob.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        // Alice still holds YT
        assertTrue(ERC20(yt).balanceOf(address(alice)) > 0);
        assertTrue(cropAdapter.tBalance(address(alice)) > 0);

        // settle series
        hevm.warp(maturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), maturity);

        // Bob closes his YT position and rewards
        bob.doCollect(yt);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(ERC20(yt).balanceOf(address(bob)), 0);

        // at this point, no rewards are left to distribute and
        // - Alice has 30 reward tokens
        // - Bob has 20 reward tokens
        assertClose(ERC20(reward).balanceOf(address(cropAdapter)), 0);

        // sponsor new Series
        uint256 newMaturity = getValidMaturity(2021, 11);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // Bob issues some target and this should represent 100% of the shares
        // but, as Alice is still holding some YTs from previous series, she will dilute Bob's rewards
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);
        reward.mint(address(cropAdapter), 50 * 1e18);
        bob.doCollect(newYt);

        // Bob should recieve the 50 newly minted reward tokens
        // but that's not true because his rewards have been diluted
        assertTrue(ERC20(reward).balanceOf(address(bob)) != 70 * 1e18);
        // Bob only receives 20 reward tokens
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        // late reconcile Alice's position
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = maturity;
        address[] memory users = new address[](1);
        users[0] = address(alice);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), (60 * tBal) / 100);

        // rewards (with bonus) should have been distributed to Alice after reconciling
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);

        // after user collecting, YTs are burnt and and reconciled amount should go to 0
        alice.doCollect(yt);
        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(yt).balanceOf(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
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
        (, address yt) = periphery.sponsorSeries(address(cropAdapter), maturity, true);
        cropAdapter.setScale(1e18);
        hevm.stopPrank();

        // Alice issues on December Series
        alice.doIssue(address(cropAdapter), maturity, (60 * tBal) / 100); // 60%
        assertEq(reward.balanceOf(address(alice)), 0);

        reward.mint(address(cropAdapter), 50 * 1e18);

        hevm.warp(block.timestamp + 12 weeks); // Current date is March

        // sponsor July Series
        uint256 newMaturity = getValidMaturity(2021, 7);
        hevm.startPrank(address(alice));
        (, address newYt) = periphery.sponsorSeries(address(cropAdapter), newMaturity, true);
        hevm.stopPrank();

        // Alice issues 0 on July series and she gets rewards from the December Series
        alice.doIssue(address(cropAdapter), newMaturity, 0);
        assertClose(reward.balanceOf(address(alice)), 50 * 1e18);

        // Bob issues on new series (no rewards are yet to be distributed to Bob)
        bob.doIssue(address(cropAdapter), newMaturity, (40 * tBal) / 100);
        assertClose(reward.balanceOf(address(bob)), 0);

        reward.mint(address(cropAdapter), 50 * 1e18);

        // Moving to July Series maturity to be able to settle the series
        hevm.warp(newMaturity + 1 seconds);
        alice.doSettleSeries(address(cropAdapter), newMaturity);

        // reconcile Alice's and Bob's positions
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), 0);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.tBalance(address(bob)), (40 * tBal) / 100);
        uint256[] memory maturities = new uint256[](1);
        maturities[0] = newMaturity;
        address[] memory users = new address[](2);
        users[0] = address(alice);
        users[1] = address(bob);
        cropAdapter.reconcile(users, maturities);
        assertEq(cropAdapter.tBalance(address(alice)), (60 * tBal) / 100);
        assertEq(cropAdapter.tBalance(address(bob)), 0);
        assertEq(cropAdapter.reconciledAmt(address(alice)), 0);
        assertEq(cropAdapter.reconciledAmt(address(bob)), (40 * tBal) / 100);

        // Both Alice and Bob should get their rewards
        assertClose(reward.balanceOf(address(alice)), 50 * 1e18);
        assertClose(reward.balanceOf(address(bob)), 20 * 1e18);

        // Alice should still be able to collect her rewards from
        // the December series (30 reward tokens)
        alice.doIssue(address(cropAdapter), maturity, 0);
        assertClose(reward.balanceOf(address(alice)), 80 * 1e18);
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
