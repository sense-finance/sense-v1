// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { CAdapter, CTokenLike, PriceOracleLike } from "../../adapters/compound/CAdapter.sol";
import { BaseAdapter } from "../../adapters/BaseAdapter.sol";

import { Assets } from "../test-helpers/Assets.sol";
import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { User } from "../test-helpers/User.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";

interface ComptrollerLike {
    function updateContributorRewards(address contributor) external;

    function compContributorSpeeds(address contributor) external view returns (uint256);

    function _setContributorCompSpeed(address contributor, uint256 compSpeed) external;

    function admin() external view returns (address);

    function compAccrued(address usr) external view returns (uint256);
}

contract CAdapterTestHelper is LiquidityHelper, DSTest {
    CAdapter internal cDaiAdapter;
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
        address target = Assets.cDAI;
        address underlying = CTokenLike(Assets.cDAI).underlying();
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: Assets.RARI_ORACLE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        cDaiAdapter = new CAdapter(address(divider), target, underlying, ISSUANCE_FEE, adapterParams, Assets.COMP); // Compound adapter

        // Create a CAdapter for an underlying token (USDC) with a non-standard number of decimals
        target = Assets.cUSDC;
        underlying = CTokenLike(Assets.cUSDC).underlying();
        cUsdcAdapter = new CAdapter(address(divider), target, underlying, ISSUANCE_FEE, adapterParams, Assets.COMP); // Compound adapter

        target = Assets.cETH;
        underlying = Assets.WETH;
        adapterParams.minm = 0;
        cEthAdapter = new CAdapter(address(divider), target, underlying, ISSUANCE_FEE, adapterParams, Assets.COMP); // Compound adapter
    }
}

contract CAdapters is CAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetCAdapterScale() public {
        CTokenLike underlying = CTokenLike(Assets.DAI);
        CTokenLike ctoken = CTokenLike(Assets.cDAI);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ctoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(cDaiAdapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleLike oracle = PriceOracleLike(Assets.MASTER_PRICE_ORACLE);
        uint256 price = oracle.price(Assets.DAI);
        assertEq(cDaiAdapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cDAI).balanceOf(address(this));

        ERC20(Assets.cDAI).approve(address(cDaiAdapter), tBalanceBefore);
        uint256 rate = CTokenLike(Assets.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        cDaiAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.cDAI).balanceOf(address(this));

        ERC20(Assets.DAI).approve(address(cDaiAdapter), uBalanceBefore);
        uint256 rate = CTokenLike(Assets.cDAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        cDaiAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cDAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    // test with cETH
    function testMainnetCETHAdapterScale() public {
        CTokenLike underlying = CTokenLike(Assets.WETH);
        CTokenLike ctoken = CTokenLike(Assets.cETH);

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
        uint256 rate = CTokenLike(Assets.cETH).exchangeRateCurrent();
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
        uint256 rate = CTokenLike(Assets.cETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        cEthAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.cETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    event DistributedBorrowerComp(
        address indexed cToken,
        address indexed borrower,
        uint256 compDelta,
        uint256 compBorrowIndex
    );

    event DistributedSupplierComp(
        address indexed cToken,
        address indexed supplier,
        uint256 compDelta,
        uint256 compSupplyIndex
    );

    function testMainnetNotifyCAdapter() public {
        divider.addAdapter(address(cEthAdapter));
        divider.setGuard(address(cEthAdapter), 100e18);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        giveTokens(Assets.DAI, 1e18, hevm);
        ERC20(Assets.DAI).approve(address(divider), type(uint256).max);
        divider.initSeries(address(cEthAdapter), maturity, address(this));

        address target = cEthAdapter.target();
        giveTokens(target, 1e18, hevm);
        ERC20(target).approve(address(divider), type(uint256).max);
        divider.issue(address(cEthAdapter), maturity, 1e18);

        hevm.prank(ComptrollerLike(Assets.COMPTROLLER).admin());
        ComptrollerLike(Assets.COMPTROLLER)._setContributorCompSpeed(address(cEthAdapter), 1e18);

        hevm.roll(block.number + 10);
        ComptrollerLike(Assets.COMPTROLLER).updateContributorRewards(address(cEthAdapter));

        // Expect a cETH distributed event when notifying
        hevm.expectEmit(true, true, false, false);
        emit DistributedBorrowerComp(address(target), address(cEthAdapter), 0, 0);
        hevm.expectEmit(true, true, false, false);
        emit DistributedSupplierComp(address(target), address(cEthAdapter), 0, 0);

        // Become the divider
        hevm.prank(address(divider));
        cEthAdapter.notify(address(0), 0, true);

        hevm.roll(block.number + 10);
        // Expect a cETH distributed event when notifying
        hevm.expectEmit(true, true, false, false);
        emit DistributedBorrowerComp(address(target), address(cEthAdapter), 0, 0);
        hevm.expectEmit(true, true, false, false);
        emit DistributedSupplierComp(address(target), address(cEthAdapter), 0, 0);

        // Become the divider
        hevm.prank(address(divider));
        cEthAdapter.notify(address(0), 0, true);
    }

    function testFailMainnetSkipClaimRewardIfAlreadyCalled() public {
        // Become the divider
        hevm.startPrank(address(divider));
        address target = cEthAdapter.target();

        // Expect a cETH distributed event when notifying
        hevm.expectEmit(true, true, false, false);
        emit DistributedBorrowerComp(address(target), address(cEthAdapter), 0, 0);
        hevm.expectEmit(true, true, false, false);
        emit DistributedSupplierComp(address(target), address(cEthAdapter), 0, 0);

        cEthAdapter.notify(address(0), 0, true);

        // Should fail to expect a cETH distributed event when notifying again in the same block
        hevm.expectEmit(true, true, false, false);
        emit DistributedBorrowerComp(address(target), address(cEthAdapter), 0, 0);
        hevm.expectEmit(true, true, false, false);
        emit DistributedSupplierComp(address(target), address(cEthAdapter), 0, 0);

        cEthAdapter.notify(address(0), 0, true);
    }

    function testMainnet18Decimals() public {
        // Scale is in 18 decimals when the Underlying has 18 decimals (WETH) ----

        // Mint this address some cETH & give the adapter approvals (note all cTokens have 8 decimals)
        giveTokens(Assets.cETH, ONE_CTOKEN, hevm);
        ERC20(Assets.cETH).approve(address(cEthAdapter), ONE_CTOKEN);

        uint256 wethOut = cEthAdapter.unwrapTarget(ONE_CTOKEN);
        // WETH is in 18 decimals, so the scale and the "WETH out" from unwrapping a single
        // cToken should be the same
        assertEq(cEthAdapter.scale(), wethOut);
        // Sanity check
        assertEq(ERC20(Assets.WETH).decimals(), 18);

        // Scale is in 18 decimals when the Underlying has a non-standard number of decimals (6 for USDC) ----

        giveTokens(Assets.cUSDC, ONE_CTOKEN, hevm);
        ERC20(Assets.cUSDC).approve(address(cUsdcAdapter), ONE_CTOKEN);

        uint256 usdcOut = cUsdcAdapter.unwrapTarget(ONE_CTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((cUsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(Assets.USDC).decimals(), 6);
    }
}
