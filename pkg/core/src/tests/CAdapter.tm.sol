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
    CAdapter internal adapter;
    CAdapter internal cethAdapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    uint8 public constant MODE = 0;
    uint256 public constant DELTA = 150;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        address[] memory assets = new address[](4);
        assets[0] = Assets.DAI;
        assets[1] = Assets.cDAI;
        assets[2] = Assets.cETH;
        assets[3] = Assets.WETH;
        addLiquidity(assets);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        // cdai adapter
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

        cethAdapter = new CAdapter(); // compound adapter
        adapterParams = BaseAdapter.AdapterParams({
            target: Assets.cETH,
            delta: DELTA,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0
        });
        cethAdapter.initialize(address(divider), adapterParams, Assets.COMP);
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetCAdapterScale() public {
        CTokenInterface underlying = CTokenInterface(Assets.DAI);
        CTokenInterface ctoken = CTokenInterface(Assets.cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent().fdiv(10**(18 - 8 + uDecimals), 10**uDecimals);
        assertEq(adapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleInterface oracle = PriceOracleInterface(Assets.RARI_ORACLE);
        uint256 price = oracle.price(Assets.DAI);
        assertEq(adapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
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

    function testMainnetWrapUnderlying() public {
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

    // test with cETH
    function testMainnetCETHAdapterScale() public {
        CTokenInterface underlying = CTokenInterface(Assets.WETH);
        CTokenInterface ctoken = CTokenInterface(Assets.cETH);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent().fdiv(10**(18 - 8 + uDecimals), 10**uDecimals);
        assertEq(cethAdapter.scale(), scale);
    }

    function testMainnetCETHGetUnderlyingPrice() public {
        assertEq(cethAdapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetCETHUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cETH).balanceOf(address(this));

        ERC20(Assets.cETH).approve(address(cethAdapter), tBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        cethAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetCETHWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cETH).balanceOf(address(this));

        ERC20(Assets.WETH).approve(address(cethAdapter), uBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        cethAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }
}
