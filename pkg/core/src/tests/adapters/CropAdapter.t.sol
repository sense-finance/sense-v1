// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Divider } from "../../Divider.sol";
import { YT } from "../../tokens/YT.sol";

import { MockAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { MockTarget } from "../test-helpers/mocks/MockTarget.sol";
import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";

contract CropAdapters is TestHelper {
    using FixedMath for uint256;

    function setUp() public virtual override {
        super.setUp();

        // freeze scale to 1e18 (only for non 4626 targets)
        if (!is4626) adapter.setScale(1e18);
    }

    function testAdapterHasParams() public {
        MockToken underlying = new MockToken("Dai", "DAI", mockUnderlyingDecimals);
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

        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            !is4626 ? target.underlying() : target.asset(),
            ISSUANCE_FEE,
            adapterParams,
            address(reward)
        );
        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = adapter.adapterParams();
        assertEq(adapter.reward(), address(reward));
        assertEq(adapter.name(), "Compound Dai Adapter");
        assertEq(adapter.symbol(), "cDAI-adapter");
        assertEq(adapter.target(), address(target));
        assertEq(adapter.underlying(), address(underlying));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(adapter.mode(), MODE);
    }

    // distribution tests
    function testDistribution() public {
        uint256 maturity = getValidMaturity(2021, 10);
        periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, 60 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 40 * 1e18);

        reward.mint(address(adapter), 50 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 0 * 1e18);

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);
    }

    function testDistributionSimple() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 0 * 1e18);

        reward.mint(address(adapter), 10 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);

        divider.issue(address(adapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);

        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);

        divider.issue(address(adapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 10 * 1e18);

        reward.mint(address(adapter), 10 * 1e18);

        divider.issue(address(adapter), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 20 * 1e18);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, 60 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 40 * 1e18);

        reward.mint(address(adapter), 50 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 0);

        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(alice), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 20 * 1e18);

        reward.mint(address(adapter), 50e18);

        divider.issue(address(adapter), maturity, 20 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(alice), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 40 * 1e18);

        reward.mint(address(adapter), 30 * 1e18);

        divider.issue(address(adapter), maturity, 0 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(alice), 80 * 1e18);
        assertClose(ERC20(reward).balanceOf(bob), 50 * 1e18);

        divider.combine(address(adapter), maturity, ERC20(yt).balanceOf(alice));
    }

    function testDistributionSimpleCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, 60 * 1e18);
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(bob), 0);

        reward.mint(address(adapter), 60 * 1e18);

        hevm.prank(bob);
        YT(yt).collect();
        assertClose(reward.balanceOf(bob), 24 * 1e18);
    }

    function testDistributionCollectAndTransferMultiStep() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address yt) = periphery.sponsorSeries(address(adapter), maturity, true);

        divider.issue(address(adapter), maturity, 60 * 1e18);
        // bob issues 40, now the pool is 40% bob and 60% alice
        hevm.prank(bob);
        divider.issue(address(adapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(bob), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(adapter), 60 * 1e18);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        hevm.prank(jim);
        divider.issue(address(adapter), maturity, 100 * 1e18);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(adapter), 100 * 1e18);

        // bob transfers all of his Yield to jim
        // now the pool is 70% jim and 30% alice
        uint256 bytBal = ERC20(yt).balanceOf(bob);
        hevm.prank(bob);
        MockToken(yt).transfer(jim, bytBal);
        // bob collected on transfer, so he should now
        // have his 24 rewards from the first drop, and 20 from the second
        assertClose(reward.balanceOf(bob), 44 * 1e18);

        // jim should have those 50 from the second airdrop (collected automatically when bob transferred to him)
        assertClose(reward.balanceOf(jim), 50 * 1e18);

        // similarly, once alice collects, she should have her 36 fom the first airdrop and 30 from the second
        YT(yt).collect();
        assertClose(reward.balanceOf(alice), 66 * 1e18);

        // now if another airdop happens, jim should get shares proportional to his new yt balance
        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after bob has transferred to jim
        // 30 should go to alice and 70 to jim
        reward.mint(address(adapter), 100 * 1e18);
        hevm.prank(jim);
        YT(yt).collect();
        assertClose(reward.balanceOf(jim), 120 * 1e18);
        YT(yt).collect();
        assertClose(reward.balanceOf(alice), 96 * 1e18);
    }
}
