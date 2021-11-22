// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { Divider, TokenHandler } from "../Divider.sol";
import { CAdapter, CTokenInterface, PriceOracleInterface } from "../adapters/compound/CAdapter.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";

import { Assets } from "./test-helpers/Assets.sol";
import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";

contract CAdapterTestHelper is LiquidityHelper, DSTest {
    CAdapter adapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    uint8 public constant MODE = 0;
    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        address[] memory assets = new address[](1);
        assets[0] = Assets.cDAI;
        addLiquidity(assets);
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));
        adapter = new CAdapter(); // compound adapter
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: Assets.cDAI,
            delta: DELTA,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0
        });
        adapter.initialize(address(divider), adapterParams, Assets.COMP);
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testCAdapterInitialize() public {
        adapter = new CAdapter(); // compound adapter
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: Assets.cDAI,
            delta: DELTA,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0
        });
        adapter.initialize(address(divider), adapterParams, Assets.COMP);
        assertEq(adapter.reward(), Assets.COMP);
        assertEq(adapter.divider(), address(divider));
        assertEq(adapter.name(), "Compound Dai Adapter");
        assertEq(adapter.symbol(), "cDAI-adapter");
        (
            address target,
            address oracle,
            uint256 delta,
            uint256 ifee,
            address stake,
            uint256 stakeSize,
            uint256 minm,
            uint256 maxm,
            uint8 mode
        ) = BaseAdapter(adapter).adapterParams();
        assertEq(target, Assets.cDAI);
        assertEq(oracle, Assets.RARI_ORACLE);
        assertEq(delta, DELTA);
        assertEq(ifee, ISSUANCE_FEE);
        assertEq(stake, Assets.DAI);
        assertEq(stakeSize, STAKE_SIZE);
        assertEq(minm, MIN_MATURITY);
        assertEq(maxm, MAX_MATURITY);
        assertEq(mode, 0);
    }

    function testCAdapterScale() public {
        CTokenInterface underlying = CTokenInterface(Assets.DAI);
        CTokenInterface ctoken = CTokenInterface(Assets.cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent().fdiv(10**(18 - 8 + uDecimals), 10**uDecimals);
        assertEq(adapter.scale(), scale);
    }

    function testGetUnderlyingPrice() public {
        PriceOracleInterface oracle = PriceOracleInterface(Assets.RARI_ORACLE);
        uint256 price = oracle.price(Assets.DAI);
        assertEq(adapter.getUnderlyingPrice(), price);
    }

    function testUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cDAI).balanceOf(address(this));

        ERC20(Assets.cDAI).approve(address(adapter), tBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        adapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cDAI).balanceOf(address(this));

        ERC20(Assets.DAI).approve(address(adapter), uBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        adapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }
}
