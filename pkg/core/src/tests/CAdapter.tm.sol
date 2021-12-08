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
    CAdapter internal cEthAdapter;
    CAdapter internal cUsdcAdapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice all cTokens have 8 decimals
    uint256 public constant ONE_CTOKEN = 1e8;

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
        assets[2] = Assets.WETH;
        assets[3] = Assets.cETH;
        addLiquidity(assets);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        // cdai adapter
        adapter = new CAdapter(); // Compound adapter
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

        cEthAdapter = new CAdapter(); // Compound adapter
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
        cEthAdapter.initialize(address(divider), adapterParams, Assets.COMP);

        // Create a CAdapter for an underlying token (USDC) with a non-standard number of decimals
        cUsdcAdapter = new CAdapter(); // Compound adapter
        adapterParams = BaseAdapter.AdapterParams({
            target: Assets.cUSDC,
            delta: DELTA,
            oracle: Assets.RARI_ORACLE,
            ifee: ISSUANCE_FEE,
            stake: Assets.USDC,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0
        });
        cUsdcAdapter.initialize(address(divider), adapterParams, Assets.COMP);
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetCAdapterScale() public {
        CTokenInterface underlying = CTokenInterface(Assets.DAI);
        CTokenInterface ctoken = CTokenInterface(Assets.cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent() / 10**(uDecimals - 8);
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
        uint256 scale = ctoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(cEthAdapter.scale(), scale);
    }

    function testMainnetCETHGetUnderlyingPrice() public {
        assertEq(cEthAdapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetCETHUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cETH).balanceOf(address(this));

        ERC20(Assets.cETH).approve(address(cEthAdapter), tBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        cEthAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetCETHWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cETH).balanceOf(address(this));

        ERC20(Assets.WETH).approve(address(cEthAdapter), uBalanceBefore);
        uint256 rate = CTokenInterface(Assets.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        cEthAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    function testMainnet18Decimals() public {
        // Scale is in 18 decimals when the Underlying has 18 decimals (WETH) ----

        // Mint this address some cETH & give the adapter approvals (note all cTokens have 8 decimals)
        giveTokens(Assets.cETH, ONE_CTOKEN, hevm);
        ERC20(Assets.cETH).approve(address(cEthAdapter), ONE_CTOKEN);
        
        uint256 wethOut = cEthAdapter.unwrapTarget(ONE_CTOKEN);
        // WETH is in 18 decimals, so the scale and the WETH out from unwrapping a single 
        // cToken should be the same
        assertEq(cEthAdapter.scale(), wethOut);
        // Sanity check
        assertEq(ERC20(Assets.WETH).decimals(), 18);

        // Scale is in 18 decimals when the Underlying has a non-standard number of decimals (6 for USDC) ----

        giveTokens(Assets.cUSDC, ONE_CTOKEN, hevm);
        ERC20(Assets.cUSDC).approve(address(cUsdcAdapter), ONE_CTOKEN);

        uint256 usdcOut = cUsdcAdapter.unwrapTarget(ONE_CTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the USDC out
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq(cUsdcAdapter.scale() / 1e12 * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(Assets.USDC).decimals(), 6);
    }
}
