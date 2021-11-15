// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// Testing utils
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { Divider, Adapter, ERC20Mintable } from "./Mocks.sol";
import { Hevm } from "./Hevm.sol";

// External references
import { Vault, IVault, IWETH, IAuthorizer, IAsset } from "@balancer-labs/v2-vault/contracts/Vault.sol";
import { Authorizer } from "@balancer-labs/v2-vault/contracts/Authorizer.sol";
import { FixedPoint } from "@balancer-labs/v2-solidity-utils/contracts/math/FixedPoint.sol";

// Internal references
import { SpaceFactory } from "../SpaceFactory.sol";
import { Space } from "../Space.sol";

// base DSTest plus testing utilities
contract Test is DSTest {
    function _assertClose(uint256 a, uint256 b, uint256 _tolerance) internal {
        uint256 diff = a < b ? b - a : a - b;
        if (diff > _tolerance) {
            emit log("Error: abs(a, b) < threshold not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            fail();
        }
     }
}

contract User {
    IVault vault;
    constructor(IVault _vault) public {
        vault = _vault;
    }
}

contract SpaceTest is Test {
    using FixedPoint for uint256;

    Hevm internal constant hevm  = Hevm(HEVM_ADDRESS);
    IWETH internal constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Vault internal vault;
    Space internal space;
    SpaceFactory internal spaceFactory;

    Divider internal divider;
    Adapter internal adapter;
    uint48 internal maturity;
    ERC20Mintable internal zero;
    ERC20Mintable internal target;

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
        
        (address _zero, ) = Divider(divider).series(address(adapter), maturity);
        zero   = ERC20Mintable(_zero);
        target = ERC20Mintable(adapter.getTarget());

        // mint this address Zeros and Target
        zero.mint(  address(this), 100e18);
        target.mint(address(this), 100e18);
        // max approve the balancer vault to move this addresses tokens
        target.approve(address(vault), type(uint256).max);
        zero.approve(  address(vault), type(uint256).max);
     }

    function _join() public {
        _join(1e18, 1e18);
    }

    function _join(uint256 reqZeroIn, uint256 reqTargetIn) public {
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(space._token0()));
        assets[1] = IAsset(address(space._token1()));

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = type(uint256).max;
        maxAmountsIn[1] = type(uint256).max;

        (uint8 zeroi, uint8 targeti) = space.getIndices();
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[zeroi  ] = reqZeroIn;
        amountsIn[targeti] = reqTargetIn;

        uint256[] memory dueProtocolFeeAmounts = new uint256[](2);
        dueProtocolFeeAmounts[0] = 0;
        dueProtocolFeeAmounts[1] = 0;

        vault.joinPool(
            space.getPoolId(),
            address(this), 
            address(this), 
            IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(
                    amountsIn,
                    dueProtocolFeeAmounts
                ),
                fromInternalBalance: false
            })
        );
    }

    function _swapIn(bool zeroIn) public {
        _swapIn(zeroIn, 1e18);
    }

    function _swapIn(bool zeroIn, uint256 amount) public {
        vault.swap(
            IVault.SingleSwap({
                poolId: space.getPoolId(),
                kind: IVault.SwapKind.GIVEN_IN,
                assetIn: IAsset(zeroIn  ? address(zero) : address(target)),
                assetOut: IAsset(zeroIn ? address(target) : address(zero)),
                amount: amount,
                userData: "0x" 
            }),
            IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            }), 
            0, // `limit` – no min expectations of return for testing GIVEN_IN
            type(uint256).max // `deadline` – no deadline
        );
    }

    function test_join_once() public {
        _join();

        // for the pool's first join –--
        // it moved Target out of this account
        assertEq(target.balanceOf(address(this)), 99e18);

        // and it minted this account BPT tokens equal to the value of underlying
        // deposited (inital scale is 1e18, so it's one-to-one)
        _assertClose(space.balanceOf(address(this)), 1e18, 1e6);

        // but it did not move any Zeros
        assertEq(zero.balanceOf(address(this)), 100e18);
    }

    function test_join_multi_no_swaps() public {
        // join once
        _join();
        // join again after no swaps 
        _join();

        // if the pool has been joined a second time and no swaps have occured –--
        // it moved more Target out of this account
        assertEq(target.balanceOf(address(this)), 98e18);

        // and it minted this account more BPT tokens
        _assertClose(space.balanceOf(address(this)), 2e18, 1e6);

        // but it still did not move any Zeros
        assertEq(zero.balanceOf(address(this)), 100e18);
    }

    function test_simple_swaps_in() public {
        // join once
        _join();

        // can't swap Target in b/c there aren't ever any Zeros to get out after the first join
        try this._swapIn(false) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001");
        }

        // can successfully swap Zeros in
        _swapIn(true);
        uint256 expectedTargetOut = 999999537591593384;

        // swapped one Zero in
        assertEq(zero.balanceOf(address(this)), 99e18);

        // received less than one Target
        assertEq(target.balanceOf(address(this)), 99e18 + expectedTargetOut);

        (, uint256[] memory balances, ) = vault.getPoolTokens(space.getPoolId());
        (uint8 zeroi, uint8 targeti) = space.getIndices();

        // pool balances reflect the user's balances
        assertEq(balances[zeroi  ], 1e18);
        assertEq(balances[targeti], 1e18 - expectedTargetOut);

        // can not swap a full Target in
        try this._swapIn(false) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "BAL#001");
        }

        // can successfully swap a partial Target in
        _swapIn(false, 0.5e18);
        uint256 expectedZeroOut = 500000338565261923;

        assertEq(target.balanceOf(address(this)), 99e18 + expectedTargetOut - 0.5e18);
        assertEq(zero.balanceOf(address(this)), 99e18 + expectedZeroOut);
    }

    // function test_simple_swaps_out() public {

    // }

    // function test_join_multi_swaps() public {
        // // if the pool has been joined a second time and no swaps have occured –--
        // // it moved more Target out of this account
        // assertEq(target.balanceOf(address(this)), 98e18);

        // // and it minted this account more BPT tokens
        // _assertClose(space.balanceOf(address(this)), 2e18, 1e6);

        // // but it still did not move any Zeros
        // assertEq(zero.balanceOf(address(this)), 100e18);
    // }

    // buy_slippage_limit
    // max base_in
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