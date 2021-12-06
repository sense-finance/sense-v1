// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Testing utils
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { MockDividerSpace, MockAdapterSpace, ERC20Mintable } from "./utils/Mocks.sol";
import { VM } from "./utils/VM.sol";
import { User } from "./utils/User.sol";

// External references
import { Vault, IVault, IWETH, IAuthorizer, IAsset, IProtocolFeesCollector } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Authentication } from "@balancer-labs/v2-solidity-utils/contracts/helpers/Authentication.sol";
import { IERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";
import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";

// Internal references
import { SpaceFactory } from "../SpaceFactory.sol";
import { Space } from "../Space.sol";

// Base DSTest plus a few extra features
contract Test is DSTest {
    function assertClose(
        uint256 a,
        uint256 b,
        uint256 _tolerance
    ) internal {
        uint256 diff = a < b ? b - a : a - b;
        if (diff > _tolerance) {
            emit log("Error: abs(a, b) < tolerance not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("  Tolerance", _tolerance);
            emit log_named_uint("    Actual", a);
            fail();
        }
    }

    function fuzzWithBounds(
        uint256 amount,
        uint256 lBound,
        uint256 uBound
    ) internal returns (uint256) {
        return lBound + (amount % (uBound - lBound));
    }
}

contract SpaceTest is Test {
    using FixedPoint for uint256;

    VM internal constant vm = VM(HEVM_ADDRESS);
    IWETH internal constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Vault internal vault;
    Space internal space;
    SpaceFactory internal spaceFactory;

    MockDividerSpace internal divider;
    MockAdapterSpace internal adapter;
    uint48 internal maturity;
    ERC20Mintable internal zero;
    ERC20Mintable internal target;
    Authorizer internal authorizer;

    User internal jim;
    User internal ava;
    User internal sid;

    uint256 internal ts;
    uint256 internal g1;
    uint256 internal g2;

    function setUp() public {
        // init normalized starting conditions
        vm.warp(0);
        vm.roll(0);

        // create mocks
        divider = new MockDividerSpace(18);
        adapter = new MockAdapterSpace(18);

        ts = FixedPoint.ONE.divDown(FixedPoint.ONE * 31622400); // 1 / 1 year in seconds
        // 0.95 for selling underlying
        g1 = (FixedPoint.ONE * 950).divDown(FixedPoint.ONE * 1000);
        // 1 / 0.95 for selling Zeros
        g2 = (FixedPoint.ONE * 1000).divDown(FixedPoint.ONE * 950);

        maturity = 15811200; // 6 months in seconds

        authorizer = new Authorizer(address(this));
        vault = new Vault(authorizer, weth, 0, 0);
        spaceFactory = new SpaceFactory(vault, address(divider), ts, g1, g2);

        space = Space(spaceFactory.create(address(adapter), maturity));

        (address _zero, , , , , , , , ) = MockDividerSpace(divider).series(address(adapter), maturity);
        zero = ERC20Mintable(_zero);
        target = ERC20Mintable(adapter.getTarget());

        // mint this address Zeros and Target
        // max approve the balancer vault to move this addresses tokens

        zero.mint(address(this), 100e18);
        target.mint(address(this), 100e18);
        target.approve(address(vault), type(uint256).max);
        zero.approve(address(vault), type(uint256).max);

        jim = new User(vault, space, zero, target);
        zero.mint(address(jim), 100e18);
        target.mint(address(jim), 100e18);

        ava = new User(vault, space, zero, target);
        zero.mint(address(ava), 100e18);
        target.mint(address(ava), 100e18);

        sid = new User(vault, space, zero, target);
        zero.mint(address(sid), 100e18);
        target.mint(address(sid), 100e18);
    }

    function testJoinOnce() public {
        jim.join();

        // for the pool's first join –--
        // it moved Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 99e18);

        // and it minted jim's account BPT tokens equal to the value of underlying
        // deposited (inital scale is 1e18, so it's one-to-one)
        assertClose(space.balanceOf(address(jim)), 1e18, 1e6);

        // but it did not move any Zeros
        assertEq(zero.balanceOf(address(jim)), 100e18);
    }

    function testJoinMultiNoSwaps() public {
        // join once
        jim.join();
        // join again after no swaps
        jim.join();

        // if the pool has been joined a second time and no swaps have occured –--
        // it moved more Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 98e18);

        // and it minted jim's account more BPT tokens
        assertClose(space.balanceOf(address(jim)), 2e18, 1e6);

        // but it still did not move any Zeros
        assertEq(zero.balanceOf(address(jim)), 100e18);
    }

    function testSimpleSwapIn() public {
        // join once (first join is always Target-only)
        jim.join();

        // can't swap any Target in b/c there aren't ever any Zeros to get out after the first join
        try jim.swapIn(false, 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001");
        }

        // can successfully swap Zeros in
        jim.swapIn(true);
        // fixed amount in, variable amount out
        uint256 expectedTargetOut = 646139118808709566;

        // swapped one Zero in
        assertEq(zero.balanceOf(address(jim)), 99e18);
        // received less than one Target
        assertEq(target.balanceOf(address(jim)), 99e18 + expectedTargetOut);

        (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
        (uint8 zeroi, uint8 targeti) = space.getIndices();

        // pool balances reflect the user's balances
        assertEq(balances[zeroi], 1e18);
        assertEq(balances[targeti], 1e18 - expectedTargetOut);

        // can not swap a full Target in
        try jim.swapIn(false) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001"); // sub overflow
        }

        // can successfully swap a partial Target in
        jim.swapIn(false, 0.5e18);
        uint256 expectedZeroOut = 804788983856909903;

        assertEq(target.balanceOf(address(jim)), 99e18 + expectedTargetOut - 0.5e18);
        assertEq(zero.balanceOf(address(jim)), 99e18 + expectedZeroOut);
    }

    function testSimpleSwapsOut() public {
        jim.join();

        // can't swap any Zeros out b/c there aren't any Zeros to get out after the first join
        try jim.swapOut(false, 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "Too few reserves");
        }

        // can successfully swap Target out
        jim.swapOut(true, 0.1e18);
        // fixed amount out, variable amount in
        uint256 expectedZerosIn = 105559160849361394; // 0.1055

        // received 0.1 Target
        assertEq(target.balanceOf(address(jim)), 99e18 + 0.1e18);

        assertEq(zero.balanceOf(address(jim)), 100e18 - expectedZerosIn);
    }

    function testExitOnce() public {
        jim.join();
        // max exit
        jim.exit(space.balanceOf(address(jim)));

        // for the pool's first exit –--
        // it moved Zeros back to jim's account
        assertEq(zero.balanceOf(address(jim)), 100e18);
        // and it took all of jim's account's BPT back
        assertEq(space.balanceOf(address(jim)), 0);
        // it moved almost all Target back to this account (locked MINIMUM_BPT permanently)
        assertClose(target.balanceOf(address(jim)), 100e18, 1e6);
    }

    function testJoinSwapExit() public {
        jim.join();

        // swap out 0.1 Target
        jim.swapOut(true, 0.1e18);

        // max exit
        jim.exit(space.balanceOf(address(jim)));

        // for the pool's first exit –--
        // it moved Zeros back to jim's account (less rounding losses)
        assertClose(zero.balanceOf(address(jim)), 100e18, 1e6);
        // and it took all of jim's account's BPT back
        assertEq(space.balanceOf(address(jim)), 0);
        // it moved almost all Target back to this account (locked MINIMUM_BPT permanently)
        assertClose(target.balanceOf(address(jim)), 100e18, 1e6);
    }

    function testMultiPartyJoinSwapExit() public {
        // Jim tries to join 1 of each (should be Target-only)
        jim.join();

        // the pool moved one Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 99e18);

        // swap 1 Zero in
        sid.swapIn(true);

        // Ava tries to Join 1 of each (should take 1 Zero and some amount of Target)
        ava.join();
        assertGe(target.balanceOf(address(ava)), 99e18);
        assertEq(zero.balanceOf(address(ava)), 99e18);

        // swap 1 Zero in

        sid.swapIn(true);

        // Ava tries to Join 1 of each (should take 1 Zero and even less Target than last time)
        uint256 targetPreJoin = target.balanceOf(address(ava));
        ava.join();
        assertGe(target.balanceOf(address(ava)), 99e18);
        // should have joined less Target than last time
        assertGt(100e18 - targetPreJoin, targetPreJoin - target.balanceOf(address(ava)));
        // should have joined Target / Zeros at the ratio of the pool
        assertEq(zero.balanceOf(address(ava)), 98e18);
        (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
        (uint8 zeroi, uint8 targeti) = space.getIndices();
        // all tokens are 18 decimals in `setUp`
        uint256 targetPerZero = (balances[targeti] * 1e18) / balances[zeroi];
        // targetPerZero * 1 = Target amount in for 1 Zero in
        assertEq(target.balanceOf(address(ava)), targetPreJoin - targetPerZero);

        // Jim and ava exit
        jim.exit(space.balanceOf(address(jim)));
        ava.exit(space.balanceOf(address(ava)));

        // can't swap after liquidity has been removed
        try sid.swapIn(true, 1e12) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#006");
        }

        try sid.swapOut(false, 1e12) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#006");
        }

        // The first swap only took Target from Jim, so he'll have fewer Target but more Zeros
        assertClose(target.balanceOf(address(jim)), 99.2e18, 1e17);
        assertClose(target.balanceOf(address(ava)), 99.8e18, 1e17);
        assertClose(zero.balanceOf(address(jim)), 101.5e18, 1e12);
        assertClose(zero.balanceOf(address(ava)), 100.5e18, 1e12);
    }

    function testSpaceFees() public {
        // Target in
        jim.join(0, 20e18);

        // Init some Zeros in via swap
        sid.swapIn(true, 4e18);

        // Try as much of both in as possible
        jim.join(20e18, 20e18);

        // We can determine the implied price of Zeros in Target by making a very small swap
        uint256 zeroPrice = sid.swapIn(true, 0.0001e18).divDown(0.0001e18);

        uint256 balance = 100e18;
        uint256 startingPositionValue = balance + balance.mulDown(zeroPrice);

        // price execution is getting worse for zero out
        uint256 targetInFor1ZeroOut = 0;
        for (uint256 i = 0; i < 20; i++) {
            uint256 _targetInFor1ZeroOut = ava.swapOut(false);
            assertGt(_targetInFor1ZeroOut, targetInFor1ZeroOut);
            targetInFor1ZeroOut = _targetInFor1ZeroOut;
            // swap the zeros back in
            ava.swapIn(true, 1e18);
        }

        // price execution is getting worse for target out
        uint256 zeroInFor1TargetOut = 0;
        for (uint256 i = 0; i < 20; i++) {
            // price execution is getting worse
            uint256 _zeroInFor1TargetOut = ava.swapOut(true);
            assertGt(_zeroInFor1TargetOut, zeroInFor1TargetOut);
            zeroInFor1TargetOut = _zeroInFor1TargetOut;
            // swap the target back in
            ava.swapIn(false, 1e18);
        }

        // price execution is getting worse for zero in
        uint256 targetOutFor1ZeroIn = type(uint256).max;
        for (uint256 i = 0; i < 20; i++) {
            // price execution is getting worse
            uint256 _targetOutFor1ZeroIn = ava.swapIn(true);
            assertLt(_targetOutFor1ZeroIn, targetOutFor1ZeroIn);
            targetOutFor1ZeroIn = _targetOutFor1ZeroIn;
            // swap the target back in
            ava.swapIn(false, _targetOutFor1ZeroIn);
        }

        // price execution is getting worse for target in
        uint256 zeroOutFor1TargetIn = type(uint256).max;
        for (uint256 i = 0; i < 20; i++) {
            // price execution is getting worse
            uint256 _zeroOutFor1TargetIn = ava.swapIn(false);
            assertLt(_zeroOutFor1TargetIn, zeroOutFor1TargetIn);
            zeroOutFor1TargetIn = _zeroOutFor1TargetIn;
            // swap the zeros back in
            ava.swapIn(true, _zeroOutFor1TargetIn);
        }

        jim.exit(space.balanceOf(address(jim)));
        uint256 currentPositionValue = target.balanceOf(address(jim)) + zero.balanceOf(address(jim)).mulDown(zeroPrice);
        assertGt(currentPositionValue, startingPositionValue);
    }

    function testApproachesOne() public {
        // Target in
        jim.join(0, 10e18);

        // Init some Zeros in
        sid.swapIn(true, 5.5e18);

        // Try as much of both in as possible
        jim.join(10e18, 10e18);

        vm.warp(maturity - 1);

        assertClose(sid.swapIn(true), 1e18, 1e12);
        assertClose(sid.swapIn(false), 1e18, 1e12);
    }

    function testProtocolFees() public {
        IProtocolFeesCollector protocolFeesCollector = vault.getProtocolFeesCollector();

        // grant protocolFeesCollector.setSwapFeePercentage role
        bytes32 actionId = Authentication(address(protocolFeesCollector)).getActionId(
            protocolFeesCollector.setSwapFeePercentage.selector
        );
        authorizer.grantRole(actionId, address(this));
        protocolFeesCollector.setSwapFeePercentage(0.1e18);

        jim.join(0, 10e18);

        sid.swapIn(true, 5.5e18);

        jim.join(10e18, 10e18);

        ava.swapOut(false);
        ava.swapIn(true);
        ava.swapOut(false);
        ava.swapIn(true);
        ava.swapOut(false);
        ava.swapIn(true);

        // no additional lp shares extracted until somebody joins or exits
        assertEq(space.balanceOf(address(protocolFeesCollector)), 7209445462227991794);
        jim.exit(space.balanceOf(address(jim)));

        assertEq(space.balanceOf(address(protocolFeesCollector)), 7834356990251230156);
    }

    // function testTinySwaps() public {
    //     // how do we know the zero price will be below 1?
    //     jim.join();

    //     uint256 _targetOut = sid.swapIn(true, 1e12);

    //     log_named_uint("_targetOut", _targetOut);

    //     assertTrue(false);
    // }

    // test_join_diff_scale_values

    // function testJoinDiffScaleValues() public {
    //     // Target in
    //     jim.join(0, 1e18);
    //     // Init Zeros
    //     sid.swapIn(true);
    //     // both in
    //     uint256 jimBptBalance = space.balanceOf(address(jim));
    //     jim.join();
    //     uint256 bptFromJoin = space.balanceOf(address(jim)) - jimBptBalance;

    //     vm.warp(2 weeks);

    //     jimBptBalance = space.balanceOf(address(jim));

    //     try jim.join() {} catch Error(string memory error) {
    //         log_string(error);
    //     }

    //     log_named_uint("bpt jim post", bptFromJoin);
    //     // log_named_uint("bpt jim post", space.balanceOf(address(jim)) - jimBptBalance);

    //     assertTrue(false);

    //     return;

    //     // get fewer lp shares for the same amount of assets
    //     // get fewer targets for the swap for the same zero in

    //     // price should never go above 1
    //     // protocol fees are calculated correctly
    // }

    function testDifferentDecimals() public {
        // Setup ----
        // set target to 9 decimals
        MockDividerSpace divider = new MockDividerSpace(9);
        // set zeros/claims to 8 decimals
        MockAdapterSpace adapter = new MockAdapterSpace(8);
        SpaceFactory spaceFactory = new SpaceFactory(vault, address(divider), ts, g1, g2);
        Space space = Space(spaceFactory.create(address(adapter), maturity));

        (address _zero, , , , , , , , ) = MockDividerSpace(divider).series(address(adapter), maturity);
        ERC20Mintable zero = ERC20Mintable(_zero);
        ERC20Mintable target = ERC20Mintable(adapter.getTarget());

        User max = new User(vault, space, zero, target);
        target.mint(address(max), 100e9);
        zero.mint(address(max), 100e8);

        User eve = new User(vault, space, zero, target);
        target.mint(address(eve), 100e9);
        zero.mint(address(eve), 100e8);

        // Test ----
        max.join(0, 1e9);

        // the pool moved one Target out of max's account
        assertEq(target.balanceOf(address(max)), 99e9);

        // swap 1 Zero in
        eve.swapIn(true, 1e8);

        // Max tries to Join 1 of each (should take 1 Zero and some amount of Target)
        max.join(1e8, 1e9);

        assertEq(zero.balanceOf(address(max)), 99e8);
        assertClose(target.balanceOf(address(max)), 98.9e9, 1e6);
    }

    // scale_goes_down

    // #nice-to-have:
    // test_space_fees_magnitude
    // test_buy_slippage_limit
    // test_join_relative_share
    // test_ts_g1_g2_variations
    // test_ys_invariant_changing_scale
    // test_ys_invariant_low_liq
    // test_ys_invariant_external_reference
}
