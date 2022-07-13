// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Periphery } from "../../Periphery.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { WstETHAdapter } from "../../adapters/implementations/lido/WstETHAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "../test-helpers/test.sol";
import { AddressBook } from "../test-helpers/AddressBook.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";

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

    function balanceOf(address owner) external returns (uint256);
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
    uint48 public constant DEFAULT_LEVEL = 31;
    uint16 public constant DEFAULT_MODE = 0;
    uint64 public constant DEFAULT_TILT = 0;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        address[] memory assets = new address[](1);
        assets[0] = AddressBook.WSTETH;
        giveTokens(AddressBook.WSTETH, 10e18, hevm);
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.RARI_ORACLE,
            stake: AddressBook.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: DEFAULT_MODE,
            tilt: DEFAULT_TILT,
            level: DEFAULT_LEVEL
        });
        adapter = new WstETHAdapter(
            address(divider),
            AddressBook.WSTETH,
            AddressBook.WETH,
            ISSUANCE_FEE,
            adapterParams
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
        uint256 ethStEth = StEthPriceFeed(AddressBook.STETHPRICEFEED).safe_price_value();
        uint256 wstETHstETH = WstETHInterface(AddressBook.WSTETH).stEthPerToken();

        uint256 scale = ethStEth.fmul(wstETHstETH);
        assertEq(adapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        uint256 price = 1e18;
        assertEq(adapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 wethBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(this));
        ERC20(AddressBook.WSTETH).approve(address(adapter), wstETHBalanceBefore);
        uint256 minDy = ICurveStableSwap(AddressBook.STETH_CURVE_POOL).get_dy(
            int128(1),
            int128(0),
            wstETHBalanceBefore.fmul(adapter.scale())
        );
        adapter.unwrapTarget(wstETHBalanceBefore);
        uint256 wstETHBalanceAfter = ERC20(AddressBook.WSTETH).balanceOf(address(this));
        uint256 wethBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));

        assertEq(wstETHBalanceAfter, 0);
        // Received at least the min expected from the curve exchange rate
        assertGt(wethBalanceAfter, wethBalanceBefore + minDy);
        // Unwraps close to what scale suggests it should
        assertClose(
            wethBalanceAfter,
            wethBalanceBefore + wstETHBalanceBefore.fmul(adapter.scale()),
            wethBalanceBefore.fmul(adapter.SLIPPAGE_TOLERANCE())
        );
    }

    function testMainnetWrapUnderlying() public {
        uint256 wethBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 stEthBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(this));
        uint256 wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(this));

        ERC20(AddressBook.WETH).approve(address(adapter), wethBalanceBefore);
        uint256 wstETH = WstETHInterface(AddressBook.WSTETH).getWstETHByStETH(wethBalanceBefore);
        adapter.wrapUnderlying(wethBalanceBefore);
        uint256 wstETHBalanceAfter = ERC20(AddressBook.WSTETH).balanceOf(address(this));
        uint256 wethBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 stEthBalanceAfter = ERC20(AddressBook.STETH).balanceOf(address(this));
        assertEq(stEthBalanceAfter, stEthBalanceBefore);
        assertEq(wethBalanceAfter, 0);
        assertClose(wstETHBalanceBefore + wstETH, wstETHBalanceAfter);
    }

    function testMainnetWrapUnwrap(uint64 wrapAmt) public {
        uint256 prebal = ERC20(AddressBook.WETH).balanceOf(address(this));
        if (wrapAmt > prebal || wrapAmt < 1e4) return;

        // Approvals
        ERC20(AddressBook.WETH).approve(address(adapter), type(uint256).max);
        ERC20(AddressBook.WSTETH).approve(address(adapter), type(uint256).max);

        // Full cycle
        adapter.unwrapTarget(adapter.wrapUnderlying(wrapAmt));
        uint256 postbal = ERC20(AddressBook.WETH).balanceOf(address(this));

        // within .1%
        assertClose(prebal, postbal, prebal.fmul(0.001e18));
    }

    function testMainnetCantSendEtherIfNotEligible() public {
        hevm.expectRevert(abi.encodeWithSelector(Errors.SenderNotEligible.selector));
        payable(address(adapter)).call{ value: 1 ether }("");
    }
}
