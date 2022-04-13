// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../Divider.sol";
import { CAdapter, CTokenLike, PriceOracleLike } from "../adapters/compound/CAdapter.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";

import { AddressBook } from "./test-helpers/AddressBook.sol";
import { DSTest } from "./test-helpers/test.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";

interface CropAdapterLike {
    function _claimReward() external;
}

contract CAdapterTestHelper is LiquidityHelper, DSTest {
    CAdapter internal adapter;
    CAdapter internal cEthAdapter;
    CAdapter internal cUsdcAdapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice all cTokens have 8 decimals
    uint256 public constant ONE_CTOKEN = 1e8;
    uint16 public constant DEFAULT_LEVEL = 31;

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        address[] memory assets = new address[](4);
        assets[0] = AddressBook.DAI;
        assets[1] = AddressBook.cDAI;
        assets[2] = AddressBook.WETH;
        assets[3] = AddressBook.cETH;
        addLiquidity(assets);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        // cdai adapter
        adapter = new CAdapter(
            address(divider),
            AddressBook.cDAI,
            AddressBook.RARI_ORACLE,
            ISSUANCE_FEE,
            AddressBook.DAI,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            0,
            0,
            DEFAULT_LEVEL,
            AddressBook.COMP
        ); // Compound adapter

        cEthAdapter = new CAdapter(
            address(divider),
            AddressBook.cETH,
            AddressBook.RARI_ORACLE,
            ISSUANCE_FEE,
            AddressBook.DAI,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            0,
            0,
            DEFAULT_LEVEL,
            AddressBook.COMP
        ); // Compound adapter

        // Create a CAdapter for an underlying token (USDC) with a non-standard number of decimals
        cUsdcAdapter = new CAdapter(
            address(divider),
            AddressBook.cUSDC,
            AddressBook.RARI_ORACLE,
            ISSUANCE_FEE,
            AddressBook.DAI,
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            0,
            0,
            DEFAULT_LEVEL,
            AddressBook.COMP
        ); // Compound adapter
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetCAdapterScale() public {
        CTokenLike underlying = CTokenLike(AddressBook.DAI);
        CTokenLike ctoken = CTokenLike(AddressBook.cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(adapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleLike oracle = PriceOracleLike(AddressBook.RARI_ORACLE);
        uint256 price = oracle.price(AddressBook.DAI);
        assertEq(adapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.cDAI).balanceOf(address(this));

        ERC20(AddressBook.cDAI).approve(address(adapter), tBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.DAI).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        adapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.DAI).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.cDAI).balanceOf(address(this));

        ERC20(AddressBook.DAI).approve(address(adapter), uBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.DAI).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        adapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.DAI).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    // test with cETH
    function testMainnetCETHAdapterScale() public {
        CTokenLike underlying = CTokenLike(AddressBook.WETH);
        CTokenLike ctoken = CTokenLike(AddressBook.cETH);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(cEthAdapter.scale(), scale);
    }

    function testMainnetCETHGetUnderlyingPrice() public {
        assertEq(cEthAdapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetCETHUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.cETH).balanceOf(address(this));

        ERC20(AddressBook.cETH).approve(address(cEthAdapter), tBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.WETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        cEthAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetCETHWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.cETH).balanceOf(address(this));

        ERC20(AddressBook.WETH).approve(address(cEthAdapter), uBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        cEthAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    event DistributedBorrowerComp(
        address indexed cToken,
        address indexed borrower,
        uint256 compDelta,
        uint256 compBorrowIndex
    );

    function testMainnetNotify() public {
        // Become the divider
        hevm.startPrank(address(divider));
        address target = cEthAdapter.target();

        // Expect a cETH distributed event when notifying
        hevm.expectEmit(true, true, false, false);
        emit DistributedBorrowerComp(address(target), address(cEthAdapter), 0, 0);
        cEthAdapter.notify(address(0), 0, true);
    }

    function testMainnet18Decimals() public {
        // Scale is in 18 decimals when the Underlying has 18 decimals (WETH) ----

        // Mint this address some cETH & give the adapter approvals (note all cTokens have 8 decimals)
        giveTokens(AddressBook.cETH, ONE_CTOKEN, hevm);
        ERC20(AddressBook.cETH).approve(address(cEthAdapter), ONE_CTOKEN);

        uint256 wethOut = cEthAdapter.unwrapTarget(ONE_CTOKEN);
        // WETH is in 18 decimals, so the scale and the "WETH out" from unwrapping a single
        // cToken should be the same
        assertEq(cEthAdapter.scale(), wethOut);
        // Sanity check
        assertEq(ERC20(AddressBook.WETH).decimals(), 18);

        // Scale is in 18 decimals when the Underlying has a non-standard number of decimals (6 for USDC) ----

        giveTokens(AddressBook.cUSDC, ONE_CTOKEN, hevm);
        ERC20(AddressBook.cUSDC).approve(address(cUsdcAdapter), ONE_CTOKEN);

        uint256 usdcOut = cUsdcAdapter.unwrapTarget(ONE_CTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((cUsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(AddressBook.USDC).decimals(), 6);
    }
}
