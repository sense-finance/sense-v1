// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { Divider, TokenHandler } from "../Divider.sol";
import { WstETHAdapter } from "../adapters/lido/WstETHAdapter.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { Assets } from "./test-helpers/Assets.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";

interface ICurveStableSwap {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
}

interface StETHInterface {
    function getSharesByPooledEth(uint256 _ethAmount) external returns (uint256);
}

interface WstETHInterface {
    function stEthPerToken() external view returns (uint256);

    function getWstETHByStETH(uint256 _stETHAmount) external returns (uint256);
}

interface StEthPriceFeed {
    function safe_price_value() external returns (uint256);
}

contract WstETHAdapterTestHelper is LiquidityHelper, DSTest {
    WstETHAdapter adapter;
    Divider internal divider;
    Periphery internal periphery;
    TokenHandler internal tokenHandler;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        address[] memory assets = new address[](1);
        assets[0] = Assets.WSTETH;
        addLiquidity(assets);
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));
        adapter = new WstETHAdapter(
            address(divider),
            Assets.WSTETH,
            Assets.RARI_ORACLE,
            ISSUANCE_FEE,
            Assets.DAI,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            0,
            0
        ); // wstETH adapter
    }

    function sendEther(address to, uint256 amt) external returns (bool) {
        (bool success, ) = to.call{ value: amt }("");
        return success;
    }
}

contract WstETHAdapters is WstETHAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetWstETHAdapterScale() public {
        uint256 ethStEth = StEthPriceFeed(Assets.STETHPRICEFEED).safe_price_value();
        uint256 wstETHstETH = WstETHInterface(Assets.WSTETH).stEthPerToken();

        uint256 scale = ethStEth.fmul(wstETHstETH, FixedMath.WAD);
        assertEq(adapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        uint256 price = 1e18;
        assertEq(adapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 wethBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 wstETHBalanceBefore = ERC20(Assets.WSTETH).balanceOf(address(this));
        ERC20(Assets.WSTETH).approve(address(adapter), wstETHBalanceBefore);
        uint256 minDy = ICurveStableSwap(Assets.CURVESINGLESWAP).get_dy(int128(1), int128(0), wstETHBalanceBefore);
        adapter.unwrapTarget(wstETHBalanceBefore);
        uint256 wstETHBalanceAfter = ERC20(Assets.WSTETH).balanceOf(address(this));
        uint256 wethBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(wstETHBalanceAfter, 0);
        assertEq(wethBalanceBefore + minDy, wethBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        uint256 wethBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 wstETHBalanceBefore = ERC20(Assets.WSTETH).balanceOf(address(this));

        ERC20(Assets.WETH).approve(address(adapter), wethBalanceBefore);
        uint256 stETH = StETHInterface(Assets.STETH).getSharesByPooledEth(wethBalanceBefore);
        uint256 wstETH = WstETHInterface(Assets.WSTETH).getWstETHByStETH(stETH);
        adapter.wrapUnderlying(wethBalanceBefore);
        uint256 wstETHBalanceAfter = ERC20(Assets.WSTETH).balanceOf(address(this));
        uint256 wethBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(wethBalanceAfter, 0);
        assertEq(wstETHBalanceBefore + wstETH, wstETHBalanceAfter);
    }

    function testMainnetCantSendEtherIfNotEligible() public {
        Hevm(HEVM_ADDRESS).expectRevert(abi.encodeWithSelector(Errors.SenderNotEligible.selector));
        payable(address(adapter)).call{ value: 1 ether }("");
    }
}
