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
            level: DEFAULT_LEVEL,
            ts: DEFAULT_TS,
            g1: DEFAULT_G1,
            g2: DEFAULT_G2,
            oracleEnabled: true
        });

        MockCropsAdapter cropsAdapter = new MockCropsAdapter(
            address(divider),
            address(target),
            target.underlying(),
            ISSUANCE_FEE,
            adapterParams,
            rewardTokens
        );
        (
            address oracle,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            ,
            ,
            ,
            uint256 ts,
            uint256 g1,
            uint256 g2,
            bool oracleEnabled
        ) = adapter.adapterParams();
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
        assertEq(adapter.mode(), MODE);
        assertEq(adapter.tilt(), 0);
        assertEq(adapter.level(), DEFAULT_LEVEL);
        assertEq(ts, DEFAULT_TS);
        assertEq(g1, DEFAULT_G1);
        assertEq(g2, DEFAULT_G2);
        assertTrue(oracleEnabled);
    }

    // distribution tests
    function testDistribution() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 60 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 0 * 1e6);

        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);
    }

    function testDistributionSimple() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 20 * 1e6);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 60 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 40 * 1e18);

        reward.mint(address(cropsAdapter), 50 * 1e18);
        reward2.mint(address(cropsAdapter), 50 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 0);

        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 30 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 20 * 1e6);

        reward.mint(address(cropsAdapter), 50e18);
        reward2.mint(address(cropsAdapter), 50e6);

        alice.doIssue(address(cropsAdapter), maturity, 20 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 60 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 40 * 1e6);

        reward.mint(address(cropsAdapter), 30 * 1e18);
        reward2.mint(address(cropsAdapter), 30 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 80 * 1e6);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(bob)), 50 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
    }

    function testDistributionSimpleCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 60 * 1e18);
        bob.doIssue(address(cropsAdapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);

        bob.doCollect(yt);
        assertClose(reward.balanceOf(address(bob)), 24 * 1e18);
        assertClose(reward2.balanceOf(address(bob)), 24 * 1e6);
    }

    function testDistributionCollectAndTransferMultiStep() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 60 * 1e18);
        // bob issues 40, now the pool is 40% bob and 60% alice
        bob.doIssue(address(cropsAdapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);
        assertEq(reward2.balanceOf(address(bob)), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(cropsAdapter), 60 * 1e18);
        reward2.mint(address(cropsAdapter), 60 * 1e6);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(cropsAdapter), maturity, 100 * 1e18);

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

    function testDistributionAddRewardToken() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        hevm.stopPrank();
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        // add new reward token
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));
        hevm.startPrank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0 * 1e18);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0 * 1e18);

        alice.doIssue(address(cropsAdapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);
        reward3.mint(address(cropsAdapter), 10 * 1e18);

        alice.doIssue(address(cropsAdapter), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 20 * 1e6);
        assertClose(ERC20(reward3).balanceOf(address(alice)), 10 * 1e18);
    }

    function testDistributionRemoveRewardToken() public {
        uint256 maturity = getValidMaturity(2021, 10);
        hevm.startPrank(address(alice));
        (, address yt) = periphery.sponsorSeries(address(cropsAdapter), maturity, true);
        hevm.stopPrank();
        cropsAdapter.setScale(1e18);

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        // remove reward token
        rewardTokens.pop();
        hevm.startPrank(address(cropsFactory));
        cropsAdapter.setRewardTokens(rewardTokens);
        hevm.stopPrank();

        alice.doIssue(address(cropsAdapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doCombine(address(cropsAdapter), maturity, ERC20(yt).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);

        reward.mint(address(cropsAdapter), 10 * 1e18);
        reward2.mint(address(cropsAdapter), 10 * 1e6);

        alice.doIssue(address(cropsAdapter), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
        assertClose(ERC20(reward2).balanceOf(address(alice)), 10 * 1e6);
    }

    function testAddRewardsTokens() public {
        MockToken reward3 = new MockToken("Reward Token 3", "RT3", 18);
        rewardTokens.push(address(reward3));

        hevm.startPrank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory
        cropsAdapter.setRewardTokens(rewardTokens);

        assertEq(cropsAdapter.rewardTokens(0), address(reward));
        assertEq(cropsAdapter.rewardTokens(1), address(reward2));
        assertEq(cropsAdapter.rewardTokens(2), address(reward3));
    }

    function testRemoveRewardsTokens() public {
        address[] memory newRewardTokens = new address[](1);
        hevm.startPrank(address(cropsFactory)); // only cropsFactory can call `setRewardTokens` as it was deployed via cropsFactory
        cropsAdapter.setRewardTokens(newRewardTokens);
        assertEq(cropsAdapter.rewardTokens(0), address(0));
    }

    function testCantSetRewardsTokens() public {
        MockToken reward2 = new MockToken("Reward Token 2", "RT2", 18);
        rewardTokens.push(address(reward2));
        hevm.expectRevert("UNTRUSTED");
        cropsAdapter.setRewardTokens(rewardTokens);
    }
}
