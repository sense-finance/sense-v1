// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { MockAdapter } from "../test-helpers/mocks/MockAdapter.sol";
import { ERC4626 } from "../../adapters/abstract/erc4626/ERC4626.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Divider } from "../../Divider.sol";
import { TestHelper, MockTargetLike } from "../test-helpers/TestHelper.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Constants } from "../test-helpers/Constants.sol";

contract FakeAdapter is BaseAdapter {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {}

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
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

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

        MockAdapter adapter = new MockAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        );
        (address oracle, address stake, uint256 stakeSize, uint256 minm, uint256 maxm, , , ) = adapter.adapterParams();
        assertEq(adapter.name(), "Compound Dai Adapter");
        assertEq(adapter.symbol(), "cDAI-adapter");
        assertEq(adapter.target(), address(target));
        assertEq(is4626Target ? target.asset() : target.underlying(), address(underlying));
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.rewardsRecipient(), Constants.REWARDS_RECIPIENT);
        assertEq(adapter.ifee(), ISSUANCE_FEE);
        assertEq(stake, address(stake));
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(oracle, ORACLE);
        assertEq(adapter.mode(), MODE);
    }

    function testScale() public {
        if (is4626Target) return;
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function test4626Scale() public {
        if (!is4626Target) return;
        assertEq(adapter.scale(), 1e18);
    }

    function testScaleMultipleTimes() public {
        if (is4626Target) return;
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
        assertEq(adapter.scale(), adapter.INITIAL_VALUE());
    }

    function test4626ScaleMultipleTimes() public {
        assertEq(adapter.scale(), 1e18);
        assertEq(adapter.scale(), 1e18);
        assertEq(adapter.scale(), 1e18);
    }

    function testCantAddCustomAdapterToDivider() public {
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
        FakeAdapter fakeAdapter = new FakeAdapter(
            address(divider),
            address(target),
            !is4626Target ? target.underlying() : target.asset(),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        );

        vm.expectRevert("UNTRUSTED");
        fakeAdapter.doSetAdapter(divider, address(fakeAdapter));
    }

    // wrap/unwrap tests
    function testWrapUnderlying() public {
        uint256 uBal = 100 * 10**uDecimals;
        uint256 tBal = 100 * 10**tDecimals;
        underlying.mint(alice, uBal);

        ERC20(address(underlying)).safeApprove(address(adapter), type(uint256).max);
        uint256 tBalReceived = adapter.wrapUnderlying(uBal);
        assertApproxEqAbs(tBal, tBalReceived, 1);
    }

    function testUnwrapTarget() public {
        uint256 tBal = 100 * 10**tDecimals;
        uint256 uBal = 100 * 10**uDecimals;
        if (is4626Target) {
            target.deposit(uBal, alice);
        } else {
            target.mint(alice, tBal);
        }

        target.approve(address(adapter), type(uint256).max);
        uint256 uBalReceived = adapter.unwrapTarget(tBal);
        assertEq(uBal, uBalReceived);
    }

    function testSetRewardsRecipient() public {
        assertEq(adapter.rewardsRecipient(), Constants.REWARDS_RECIPIENT);

        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x123));
        adapter.setRewardsRecipient(address(0x111));

        // Can be changed by admin

        vm.expectEmit(true, true, true, true);
        emit RewardsRecipientChanged(Constants.REWARDS_RECIPIENT, address(0x111));

        vm.prank(Constants.RESTRICTED_ADMIN);
        adapter.setRewardsRecipient(address(0x111));
        assertEq(adapter.rewardsRecipient(), address(0x111));

        // Can be changed by the factory that deployed it

        vm.expectEmit(true, true, true, true);
        emit RewardsRecipientChanged(address(0x111), address(0x222));

        vm.prank(address(factory));
        adapter.setRewardsRecipient(address(0x222));
        assertEq(adapter.rewardsRecipient(), address(0x222));
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
    }

    /* ========== LOGS ========== */

    event RewardsRecipientChanged(address indexed recipient, address indexed newRecipient);
    event RewardsClaimed(address indexed token, address indexed recipient, uint256 indexed amount);
}
