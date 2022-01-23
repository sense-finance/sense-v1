// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { CropAdapter } from "../adapters/CropAdapter.sol";
import { Divider } from "../Divider.sol";

import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract FakeAdapter is BaseAdapter {
    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level
    )
        BaseAdapter(
            _divider,
            _target,
            address(1),
            _oracle,
            _ifee,
            _stake,
            _stakeSize,
            _minm,
            _maxm,
            _mode,
            _tilt,
            _level
        )
    {}

    function scale() external virtual override returns (uint256 _value) {
        return 100e18;
    }

    function scaleStored() external view virtual override returns (uint256) {
        return 100e18;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return 1e18;
    }

    function doSetAdapter(Divider d, address _adapter) public {
        d.setAdapter(_adapter, true);
    }
}

contract Adapters is TestHelper {
    using FixedMath for uint256;

    function testAdapterHasParams() public {
        MockToken underlying = new MockToken("Dai", "DAI", 18);
        MockTarget target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);
        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL,
            address(reward)
        );

        assertEq(adapter.reward(), address(reward));
        assertEq(adapter.name(), "Compound Dai Adapter");
        assertEq(adapter.symbol(), "cDAI-adapter");
        assertEq(adapter.target(), address(target));
        assertEq(adapter.underlying(), address(underlying));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.ifee(), ISSUANCE_FEE);
        assertEq(adapter.stake(), address(stake));
        assertEq(adapter.stakeSize(), STAKE_SIZE);
        assertEq(adapter.minm(), MIN_MATURITY);
        assertEq(adapter.maxm(), MAX_MATURITY);
        assertEq(adapter.oracle(), ORACLE);
        assertEq(adapter.mode(), MODE);
    }

    function testScale() public {
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function testScaleMultipleTimes() public {
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function testCantAddCustomAdapterToDivider() public {
        FakeAdapter fakeAdapter = new FakeAdapter(
            address(divider),
            address(target),
            ORACLE,
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0,
            DEFAULT_LEVEL
        );

        try fakeAdapter.doSetAdapter(divider, address(fakeAdapter)) {
            fail();
        } catch Error(string memory err) {
            assertEq(err, "UNTRUSTED");
        }
    }

    // distribution tests
    function testDistribution() public {
        uint256 maturity = getValidMaturity(2021, 10);
        sponsorSampleSeries(address(alice), maturity);
        adapter.setScale(1e18);

        alice.doIssue(address(adapter), maturity, 60 * 1e18);
        bob.doIssue(address(adapter), maturity, 40 * 1e18);

        reward.mint(address(adapter), 50 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0 * 1e18);

        bob.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        bob.doIssue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);
    }

    function testDistributionSimple() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        adapter.setScale(1e18);

        alice.doIssue(address(adapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 0 * 1e18);

        reward.mint(address(adapter), 10 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(adapter), maturity, 100 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doCombine(address(adapter), maturity, ERC20(claim).balanceOf(address(alice)));
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        alice.doIssue(address(adapter), maturity, 50 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 10 * 1e18);

        reward.mint(address(adapter), 10 * 1e18);

        alice.doIssue(address(adapter), maturity, 10 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 20 * 1e18);
    }

    function testDistributionProportionally() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        adapter.setScale(1e18);

        alice.doIssue(address(adapter), maturity, 60 * 1e18);
        bob.doIssue(address(adapter), maturity, 40 * 1e18);

        reward.mint(address(adapter), 50 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 0);

        bob.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        bob.doIssue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 30 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 20 * 1e18);

        reward.mint(address(adapter), 50e18);

        alice.doIssue(address(adapter), maturity, 20 * 1e18);
        bob.doIssue(address(adapter), maturity, 0 * 1e18);

        assertClose(ERC20(reward).balanceOf(address(alice)), 60 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 40 * 1e18);

        reward.mint(address(adapter), 30 * 1e18);

        alice.doIssue(address(adapter), maturity, 0 * 1e18);
        bob.doIssue(address(adapter), maturity, 0 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(alice)), 80 * 1e18);
        assertClose(ERC20(reward).balanceOf(address(bob)), 50 * 1e18);

        alice.doCombine(address(adapter), maturity, ERC20(claim).balanceOf(address(alice)));
    }

    function testDistributionSimpleCollect() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        adapter.setScale(1e18);

        alice.doIssue(address(adapter), maturity, 60 * 1e18);
        bob.doIssue(address(adapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);

        reward.mint(address(adapter), 60 * 1e18);

        bob.doCollect(claim);
        assertClose(reward.balanceOf(address(bob)), 24 * 1e18);
    }

    function testDistributionCollectAndTransferMultiStep() public {
        uint256 maturity = getValidMaturity(2021, 10);
        (, address claim) = sponsorSampleSeries(address(alice), maturity);
        adapter.setScale(1e18);

        alice.doIssue(address(adapter), maturity, 60 * 1e18);
        // bob issues 40, now the pool is 40% bob and 60% alice
        bob.doIssue(address(adapter), maturity, 40 * 1e18);

        assertEq(reward.balanceOf(address(bob)), 0);

        // 60 reward tokens are aridropped before jim issues
        // 24 should go to bob and 36 to alice
        reward.mint(address(adapter), 60 * 1e18);
        hevm.warp(block.timestamp + 1 days);

        // jim issues 40, now the pool is 20% bob, 30% alice, and 50% jim
        jim.doIssue(address(adapter), maturity, 100 * 1e18);

        hevm.warp(block.timestamp + 1 days);
        // 100 more reward tokens are airdropped after jim has issued
        // 20 should go to bob, 30 to alice, and 50 to jim
        reward.mint(address(adapter), 100 * 1e18);

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
        reward.mint(address(adapter), 100 * 1e18);
        jim.doCollect(claim);
        assertClose(reward.balanceOf(address(jim)), 120 * 1e18);
        alice.doCollect(claim);
        assertClose(reward.balanceOf(address(alice)), 96 * 1e18);
    }
}
