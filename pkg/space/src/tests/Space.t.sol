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
import { Errors } from "../Errors.sol";

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
    uint256 public constant INTIAL_USER_BALANCE = 100e18;

    Vault internal vault;
    Space internal space;
    SpaceFactory internal spaceFactory;

    MockDividerSpace internal divider;
    MockAdapterSpace internal adapter;
    uint256 internal maturity;
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
        // Init normalized starting conditions
        vm.warp(0);
        vm.roll(0);

        // Create mocks
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
        target = ERC20Mintable(adapter.target());

        // Mint this address Zeros and Target
        // Max approve the balancer vault to move this addresses tokens
        zero.mint(address(this), INTIAL_USER_BALANCE);
        target.mint(address(this), INTIAL_USER_BALANCE);
        target.approve(address(vault), type(uint256).max);
        zero.approve(address(vault), type(uint256).max);

        jim = new User(vault, space, zero, target);
        zero.mint(address(jim), INTIAL_USER_BALANCE);
        target.mint(address(jim), INTIAL_USER_BALANCE);

        ava = new User(vault, space, zero, target);
        zero.mint(address(ava), INTIAL_USER_BALANCE);
        target.mint(address(ava), INTIAL_USER_BALANCE);

        sid = new User(vault, space, zero, target);
        zero.mint(address(sid), INTIAL_USER_BALANCE);
        target.mint(address(sid), INTIAL_USER_BALANCE);
    }

    function testJoinOnce() public {
        jim.join();

        // For the pool's first join –--
        // It moved Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 99e18);

        // and it minted jim's account BPT tokens equal to the value of underlying
        // deposited (inital scale is 1e18, so it's one-to-one)
        assertClose(space.balanceOf(address(jim)), 1e18, 1e6);

        // but it did not move any Zeros
        assertEq(zero.balanceOf(address(jim)), 100e18);
    }

    function testJoinMultiNoSwaps() public {
        // Join once
        jim.join();
        // Join again after no swaps
        jim.join();

        // If the pool has been joined a second time and no swaps have occured –--
        // It moved more Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 98e18);

        // and it minted jim's account more BPT tokens
        assertClose(space.balanceOf(address(jim)), 2e18, 1e6);

        // but it still did not move any Zeros
        assertEq(zero.balanceOf(address(jim)), 100e18);
    }

    function testSimpleSwapIn() public {
        // Join once (first join is always Target-only)
        jim.join();

        // Can't swap any Target in b/c there aren't ever any Zeros to get out after the first join
        try jim.swapIn(false, 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SWAP_TOO_SMALL);
        }

        // Can successfully swap Zeros in
        uint256 targetOt = jim.swapIn(true);
        // Fixed amount in, variable amount out
        uint256 expectedTargetOut = 646139118808653602;

        // Swapped one Zero in
        assertEq(zero.balanceOf(address(jim)), 99e18);
        // Received less than one Target
        assertEq(targetOt, expectedTargetOut);

        (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
        (uint8 zeroi, uint8 targeti) = space.getIndices();

        // Pool balances reflect the user's balances
        assertEq(balances[zeroi], 1e18);
        assertEq(balances[targeti], 1e18 - expectedTargetOut);

        // Can not swap a full Target in
        try jim.swapIn(false) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001"); // sub overflow
        }

        // Can successfully swap a partial Target in
        uint256 zeroOut = jim.swapIn(false, 0.5e18);
        uint256 expectedZeroOut = 804788983856768174;

        assertEq(target.balanceOf(address(jim)), 99e18 + expectedTargetOut - 0.5e18);
        assertEq(zeroOut, expectedZeroOut);
    }

    function testSimpleSwapsOut() public {
        jim.join();

        // Can't swap any Zeros out b/c there aren't any Zeros to get out after the first join
        try jim.swapOut(false, 1) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001");
        }

        // Can successfully swap Target out
        uint256 zerosIn = jim.swapOut(true, 0.1e18);
        // Fixed amount out, variable amount in
        uint256 expectedZerosIn = 105559160849472541; // around 0.10556

        // Received 0.1 Target
        assertEq(target.balanceOf(address(jim)), 99e18 + 0.1e18);
        assertEq(zerosIn, expectedZerosIn);
    }

    function testExitOnce() public {
        jim.join();
        // Max exit
        jim.exit(space.balanceOf(address(jim)));

        // For the pool's first exit –--
        // It moved Zeros back to jim's account
        assertEq(zero.balanceOf(address(jim)), 100e18);
        // And it took all of jim's account's BPT back
        assertEq(space.balanceOf(address(jim)), 0);
        // It moved almost all Target back to this account (locked MINIMUM_BPT permanently)
        assertClose(target.balanceOf(address(jim)), 100e18, 1e6);
    }

    function testJoinSwapExit() public {
        jim.join();

        // Swap out 0.1 Target
        jim.swapOut(true, 0.1e18);

        // Max exit
        jim.exit(space.balanceOf(address(jim)));

        // For the pool's first exit –--
        // It moved Zeros back to jim's account (less rounding losses)
        assertClose(zero.balanceOf(address(jim)), 100e18, 1e6);
        // And it took all of jim's account's BPT back
        assertEq(space.balanceOf(address(jim)), 0);
        // It moved almost all Target back to this account (locked MINIMUM_BPT permanently)
        assertClose(target.balanceOf(address(jim)), 100e18, 1e6);
    }

    function testMultiPartyJoinSwapExit() public {
        // Jim tries to join 1 of each (should be Target-only)
        jim.join();

        // The pool moved one Target out of jim's account
        assertEq(target.balanceOf(address(jim)), 99e18);

        // Swap 1 Zero in
        sid.swapIn(true);

        // Ava tries to Join 1 of each (should take 1 Zero and some amount of Target)
        ava.join();
        assertGe(target.balanceOf(address(ava)), 99e18);
        assertEq(zero.balanceOf(address(ava)), 99e18);

        // Swap 1 Zero in

        sid.swapIn(true);

        // Ava tries to Join 1 of each (should take 1 Zero and even less Target than last time)
        uint256 targetPreJoin = target.balanceOf(address(ava));
        ava.join();
        assertGe(target.balanceOf(address(ava)), 99e18);
        // Should have joined less Target than last time
        assertGt(100e18 - targetPreJoin, targetPreJoin - target.balanceOf(address(ava)));
        // Should have joined Target / Zeros at the ratio of the pool
        assertEq(zero.balanceOf(address(ava)), 98e18);
        (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
        (uint8 zeroi, uint8 targeti) = space.getIndices();
        // All tokens are 18 decimals in `setUp`
        uint256 targetPerZero = (balances[targeti] * 1e18) / balances[zeroi];
        // TargetPerZero * 1 = Target amount in for 1 Zero in
        assertEq(target.balanceOf(address(ava)), targetPreJoin - targetPerZero);

        // Jim and ava exit
        jim.exit(space.balanceOf(address(jim)));
        ava.exit(space.balanceOf(address(ava)));

        // Can't swap after liquidity has been removed
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

        assertClose(sid.swapIn(true).mulDown(adapter.scale()), 1e18, 1e11);
        assertClose(sid.swapIn(false, uint256(1e18).divDown(adapter.scale())), 1e18, 1e11);
    }

    function testConstantSumAfterMaturity() public {
        // Target in
        jim.join(0, 10e18);

        // Init some Zeros in
        sid.swapIn(true, 5.5e18);

        // Try as much of both in as possible
        jim.join(10e18, 10e18);

        vm.warp(maturity + 1);

        assertClose(sid.swapIn(true).mulDown(adapter.scale()), 1e18, 1e7);
        assertClose(sid.swapIn(false, uint256(1e18).divDown(adapter.scale())), 1e18, 1e7);
    }

    function testCantJoinAfterMaturity() public {
        vm.warp(maturity + 1);

        try jim.join(0, 10e18) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.POOL_PAST_MATURITY);
        }
    }

    function testProtocolFees() public {
        IProtocolFeesCollector protocolFeesCollector = vault.getProtocolFeesCollector();

        // Grant protocolFeesCollector.setSwapFeePercentage role
        bytes32 actionId = Authentication(address(protocolFeesCollector)).getActionId(
            protocolFeesCollector.setSwapFeePercentage.selector
        );
        authorizer.grantRole(actionId, address(this));
        protocolFeesCollector.setSwapFeePercentage(0.1e18);

        jim.join(0, 10e18);
        sid.swapIn(true, 5.5e18);
        jim.join(10e18, 10e18);

        for (uint256 i = 0; i < 6; i++) {
            ava.swapOut(false);
            ava.swapIn(true);
        }

        // No additional lp shares extracted until somebody joins or exits
        assertEq(space.balanceOf(address(protocolFeesCollector)), 1003147415248878304);
        jim.exit(space.balanceOf(address(jim)));

        assertEq(space.balanceOf(address(protocolFeesCollector)), 1009757643907926313);

        // TODO fees don't eat into non-trade invariant growth
        // TODO fees are correctly proportioned to the fee set in the vault
        // time goes by
    }

    function testTinySwaps() public {
        jim.join(0, 10e18);
        sid.swapIn(true, 5.5e18);
        jim.join(10e18, 10e18);

        // Swaps in can fail for being too small
        try sid.swapIn(true, 1e6) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SWAP_TOO_SMALL);
        }
        try sid.swapIn(false, 1e6) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, Errors.SWAP_TOO_SMALL);
        }

        // Swaps outs don't fail, but they ask for very high amounts in
        // (rouding in favor of the LP has a big effect on small swaps)
        assertGt(sid.swapOut(true, 1e6), 2e6);
        assertGt(sid.swapOut(false, 1e6), 2e6);
    }

    function testJoinDifferentScaleValues() public {
        // Jim join Target in
        jim.join(0, 10e18);

        // Sid inits Zeros
        sid.swapIn(true, 5.5e18);

        uint256 initScale = adapter.scale();

        // Determine how much Target Jim gets for one Zero
        uint256 targetOutForOneZeroInit = jim.swapIn(true);
        // Swap that Target back in to restore the AMM state to before the prev swap
        jim.swapIn(false, targetOutForOneZeroInit);

        // Ava tries to join both in
        ava.join();
        // BPT from Ava's (1 Zero, 1 Target) join
        uint256 bptFromJoin = space.balanceOf(address(ava));
        uint256 targetInFromJoin = INTIAL_USER_BALANCE - target.balanceOf(address(ava));
        uint256 zeroInFromJoin = INTIAL_USER_BALANCE - zero.balanceOf(address(ava));

        vm.warp(1 days);
        uint256 scale1Week = adapter.scale();
        ava.join();

        // Ava's BPT out will exactly equal her first join
        // Since the Target is worth more, she essentially got fewer BPT for the same amount of Underlying
        assertClose(bptFromJoin, space.balanceOf(address(ava)) - bptFromJoin, 1e3);
        // Same amount of Target in (but it's worth more now)
        assertClose(targetInFromJoin * 2, INTIAL_USER_BALANCE - target.balanceOf(address(ava)), 1e3);
        // Same amount of Zero in
        assertClose(zeroInFromJoin * 2, INTIAL_USER_BALANCE - zero.balanceOf(address(ava)), 1e3);

        // Ava can exit her entire LP position just fine
        ava.exit(space.balanceOf(address(ava)));

        uint256 targetOutForOneZero1Week = jim.swapIn(true);
        // Gets fewer target out for one Zero when Target is worth more
        assertGt(targetOutForOneZeroInit, targetOutForOneZero1Week);
        // There is some change due to the YS invariant, but it's not much in 1 days time
        // With the rate the Target is increasing in value, its growth should account for most of the change
        // in swap rate
        assertClose(targetOutForOneZeroInit, targetOutForOneZero1Week.mulDown(scale1Week.divDown(initScale)), 1e15);
    }

    function testDifferentDecimals() public {
        // Setup ----
        // Set Zeros/Claims to 8 decimals
        MockDividerSpace divider = new MockDividerSpace(8);
        // Set Target to 9 decimals
        MockAdapterSpace adapter = new MockAdapterSpace(9);
        SpaceFactory spaceFactory = new SpaceFactory(vault, address(divider), ts, g1, g2);
        Space space = Space(spaceFactory.create(address(adapter), maturity));

        (address _zero, , , , , , , , ) = MockDividerSpace(divider).series(address(adapter), maturity);
        ERC20Mintable zero = ERC20Mintable(_zero);
        ERC20Mintable _target = ERC20Mintable(adapter.target());

        User max = new User(vault, space, zero, _target);
        _target.mint(address(max), 100e9);
        zero.mint(address(max), 100e8);

        User eve = new User(vault, space, zero, _target);
        _target.mint(address(eve), 100e9);
        zero.mint(address(eve), 100e8);

        // Test ----
        // Max joins 1 Target in
        max.join(0, 1e9);

        // The pool moved one Target out of max's account
        assertEq(_target.balanceOf(address(max)), 99e9);

        // Eve swaps 1 Zero in
        eve.swapIn(true, 1e8);

        // Max tries to Join 1 of each (should take 1 Zero and some amount of Target)
        max.join(1e8, 1e9);

        assertEq(zero.balanceOf(address(max)), 99e8);

        // Compare Target pulled from max's account to the normal, 18 decimal case
        jim.join(0, 1e18);
        sid.swapIn(true, 1e18);
        jim.join(1e18, 1e18);
        // Determine Jim's Target balance in 9 decimals
        uint256 jimTargetBalance = target.balanceOf(address(jim)) / 10**(18 - _target.decimals());

        assertClose(_target.balanceOf(address(max)), jimTargetBalance, 1e6);
    }

    function testNonMonotonicScale() public {
        adapter.setScale(1e18);
        jim.join(0, 10e18);
        sid.swapIn(true, 5.5e18);
        jim.join(10e18, 10e18);

        adapter.setScale(1.5e18);
        jim.join(10e18, 10e18);
        uint256 targetOut1 = sid.swapIn(true, 5.5e18);

        adapter.setScale(1e18);
        jim.join(10e18, 10e18);
        uint256 targetOut2 = sid.swapIn(true, 5.5e18);

        // Set scale to below the initial scale
        adapter.setScale(0.5e18);
        jim.join(10e18, 10e18);
        uint256 targetOut3 = sid.swapIn(true, 5.5e18);

        // Receive more and more Target out as the Scale value decreases
        assertGt(targetOut3, targetOut2);
        assertGt(targetOut2, targetOut1);
    }

    // testJoinExactAmount
    // testPoolFees
    // testPriceNeverAboveOne
    // testFuzzScaleValues
    // testYSInvariant
    // testTimeshift
}
