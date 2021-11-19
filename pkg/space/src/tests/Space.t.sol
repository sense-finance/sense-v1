// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Testing utils
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { Divider, Adapter, ERC20Mintable } from "./Mocks.sol";
import { Hevm } from "./Hevm.sol";

// External references
import { Vault, IVault, IWETH, IAuthorizer, IAsset } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { IERC20 } from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";
import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";

// Internal references
import { SpaceFactory } from "../SpaceFactory.sol";
import { Space } from "../Space.sol";

// base DSTest plus testing utilities
contract Test is DSTest {
    function assertClose(
        uint256 a,
        uint256 b,
        uint256 _tolerance
    ) internal {
        uint256 diff = a < b ? b - a : a - b;
        if (diff > _tolerance) {
            emit log("Error: abs(a, b) < threshold not satisfied [uint]");
            emit log_named_uint("  Expected", b);
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

contract User {
    Space space;
    IVault vault;
    ERC20Mintable zero;
    ERC20Mintable target;

    constructor(
        IVault _vault,
        Space _space,
        ERC20Mintable _zero,
        ERC20Mintable _target
    ) public {
        vault = _vault;
        space = _space;
        zero = _zero;
        target = _target;
        zero.approve(address(vault), type(uint256).max);
        target.approve(address(vault), type(uint256).max);
    }

    function join() public {
        join(1e18, 1e18);
    }

    function join(uint256 reqZeroIn, uint256 reqTargetIn) public {
        (IERC20[] memory _assets, , ) = vault.getPoolTokens(space.getPoolId());

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(_assets[0]));
        assets[1] = IAsset(address(_assets[1]));

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = type(uint256).max;
        maxAmountsIn[1] = type(uint256).max;

        (uint8 zeroi, uint8 targeti) = space.getIndices();
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[zeroi] = reqZeroIn;
        amountsIn[targeti] = reqTargetIn;

        vault.joinPool(
            space.getPoolId(),
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(amountsIn),
                fromInternalBalance: false
            })
        );
    }

    function exit(uint256 bptAmountIn) public {
        (IERC20[] memory _assets, , ) = vault.getPoolTokens(space.getPoolId());

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(_assets[0]));
        assets[1] = IAsset(address(_assets[1]));

        uint256[] memory minAmountsOut = new uint256[](2); // implicit zeros

        vault.exitPool(
            space.getPoolId(),
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: abi.encode(bptAmountIn),
                toInternalBalance: false
            })
        );
    }

    function swapIn(bool zeroIn) public {
        swapIn(zeroIn, 1e18);
    }

    function swapIn(bool zeroIn, uint256 amountIn) public {
        vault.swap(
            IVault.SingleSwap({
                poolId: space.getPoolId(),
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(zeroIn ? address(zero) : address(target)),
                assetOut: IAsset(zeroIn ? address(target) : address(zero)),
                amount: amountIn,
                userData: "0x"
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            0, // `limit` – no min expectations of return around tokens out testing GIVEN_IN
            type(uint256).max // `deadline` – no deadline
        );
    }

    function swapOut(bool zeroIn) public {
        swapIn(zeroIn, 1e18);
    }

    function swapOut(bool zeroIn, uint256 amountOut) public {
        vault.swap(
            IVault.SingleSwap({
                poolId: space.getPoolId(),
                kind: IVault.SwapKind.GIVEN_OUT,
                assetIn: IAsset(zeroIn ? address(zero) : address(target)),
                assetOut: IAsset(zeroIn ? address(target) : address(zero)),
                amount: amountOut,
                userData: "0x"
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }),
            type(uint256).max, // `limit` – no max expectations around tokens out for testing GIVEN_OUT
            type(uint256).max // `deadline` – no deadline
        );
    }
}

// Balancer errors –---
// 007: Y_OUT_OF_BOUNDS
// 004: ZERO_DIVISION
// ---------------------

contract SpaceTest is Test {
    using FixedPoint for uint256;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);
    IWETH internal constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Vault internal vault;
    Space internal space;
    SpaceFactory internal spaceFactory;

    Divider internal divider;
    Adapter internal adapter;
    uint48 internal maturity;
    ERC20Mintable internal zero;
    ERC20Mintable internal target;

    User internal jim;
    User internal ava;
    User internal sid;

    function setUp() public {
        // init normalized starting conditions
        hevm.warp(0);
        hevm.roll(0);

        // create mocks
        divider = new Divider();
        adapter = new Adapter();

        uint256 ts = FixedPoint.ONE.divDown(FixedPoint.ONE * 315576000);
        // 0.95 for selling underlying
        uint256 g1 = (FixedPoint.ONE * 95).divDown(FixedPoint.ONE * 100);
        // 1 / 0.95 for selling Zeros
        uint256 g2 = (FixedPoint.ONE * 1000).divDown(FixedPoint.ONE * 950);
        maturity = 100;

        vault = new Vault(new Authorizer(address(this)), weth, 0, 0);
        spaceFactory = new SpaceFactory(vault, address(divider), ts, g1, g2);

        space = Space(spaceFactory.create(address(adapter), maturity));

        (address _zero, , , , , , , , ) = Divider(divider).series(address(adapter), maturity);
        zero = ERC20Mintable(_zero);
        target = ERC20Mintable(adapter.getTarget());

        // mint this address Zeros and Target
        // max approve the balancer vault to move this addresses tokens

        zero.mint(address(this), 100e18);
        target.mint(address(this), 100e18);
        target.approve(address(vault), type(uint256).max);
        zero.approve(address(vault), type(uint256).max);

        jim = new User(vault, space, zero, target);
        {
            zero.mint(address(jim), 100e18);
            target.mint(address(jim), 100e18);
        }
        ava = new User(vault, space, zero, target);
        {
            zero.mint(address(ava), 100e18);
            target.mint(address(ava), 100e18);
        }
        sid = new User(vault, space, zero, target);
        {
            zero.mint(address(sid), 100e18);
            target.mint(address(sid), 100e18);
        }
    }

    function test_join_once() public {
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

    function test_join_multi_no_swaps() public {
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

    function test_simple_swap_in() public {
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
        uint256 expectedTargetOut = 999999537591593384;

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
        uint256 expectedZeroOut = 500000338565261923;

        assertEq(target.balanceOf(address(jim)), 99e18 + expectedTargetOut - 0.5e18);
        assertEq(zero.balanceOf(address(jim)), 99e18 + expectedZeroOut);
    }

    function test_simple_swaps_out() public {
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
        uint256 expectedZerosIn = 100000003341147966;

        // received 0.1 Target
        assertEq(target.balanceOf(address(jim)), 99e18 + 0.1e18);

        assertEq(zero.balanceOf(address(jim)), 100e18 - expectedZerosIn);
    }

    function test_exit_once() public {
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

    function test_join_swap_exit() public {
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

    function test_multi_party_join_swap_exit() public {
        jim.join();
        ava.join();

        // swap 1 Zero in
        sid.swapIn(true);

        // jim and ava exit
        jim.exit(space.balanceOf(address(jim)));
        ava.exit(space.balanceOf(address(ava)));

        // Can pull around half the Target from sid's swap
        assertClose(target.balanceOf(address(jim)), 99.5e18, 1e12);
        assertClose(target.balanceOf(address(ava)), 99.5e18, 1e12);
        assertClose(zero.balanceOf(address(jim)), 100.5e18, 1e12);
        assertClose(zero.balanceOf(address(ava)), 100.5e18, 1e12);
    }

    // function test_space_fees() public {
    //     // Target in
    //     jim.join(0, 10e18);

    //     // Init some Zeros in
    //     sid.swapIn(true, 9e18);

    //     // Try both in
    //     jim.join(10e18, 10e18);

    //     (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
    //     (uint8 zeroi, uint8 targeti) = space.getIndices();

    //     // pool balances reflect the user's balances
    //     log_uint(balances[zeroi]);
    //     log_uint(balances[targeti]);

    //     // Lots of swaps
    //     sid.swapIn(false, 2e18);
    //     sid.swapIn(true, 2e18);
    //     sid.swapIn(false, 2e18);
    //     sid.swapIn(true, 2e18);
    //     sid.swapIn(false, 2e18);
    //     sid.swapIn(true, 2e18);
    //     sid.swapIn(false, 2e18);
    //     sid.swapIn(true, 2e18);
    //     sid.swapIn(false, 2e18);
    //     sid.swapIn(true, 2e18);
    //     sid.swapIn(false, 2e18);

    //     jim.exit(space.balanceOf(address(jim)));
    //     log_uint(target.balanceOf(address(jim)));
    //     log_uint(zero.balanceOf(address(jim)));
    //     assertTrue(false);
    // }

    // test_protocol_fees
    // test_join_multi_swaps
    // test_buy_slippage_limit
    // test_join_slippage
    // test_exit_slippage
    // test_max_base_in
    // test_join_multi
    // test_join_exit_once
    // test_join_exit_multi
    // test_join_diff_scale_values
    // test_simple_swap_zero_in
    // test_simple_swap_target_in
    // test_simple_swap_zero_out
    // test_simple_swap_target_out
    // test_ts_g1_g2
    // test_ys_invariant_constant_scale
    // test_ys_invariant_changing_scale
    // test_ys_invariant_low_liq
    // test_ys_invariant_ex_reference
    // test_exit
}
