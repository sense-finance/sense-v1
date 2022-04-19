// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { FAdapter, FTokenLike, PriceOracleLike } from "../../adapters/fuse/FAdapter.sol";
import { BaseAdapter } from "../../adapters/BaseAdapter.sol";

import { Assets } from "../test-helpers/Assets.sol";
import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { User } from "../test-helpers/User.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";

interface CropAdapterLike {
    function _claimRewards() external;
}

interface RewardsDistributorLike {
    function accrue(ERC20 market, address user) external returns (uint256);
}

contract FAdapterTestHelper is LiquidityHelper, DSTest {
    FAdapter internal f18DaiAdapter;
    FAdapter internal f18EthAdapter;
    FAdapter internal f18UsdcAdapter;
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice all cTokens have 8 decimals
    uint256 public constant ONE_FTOKEN = 1e8;
    uint16 public constant DEFAULT_LEVEL = 31;

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        giveTokens(Assets.DAI, ONE_FTOKEN, hevm);
        giveTokens(Assets.f18DAI, ONE_FTOKEN, hevm);
        giveTokens(Assets.WETH, ONE_FTOKEN, hevm);
        giveTokens(Assets.f18ETH, ONE_FTOKEN, hevm);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: Assets.f18DAI,
            underlying: FTokenLike(Assets.f18DAI).underlying(),
            oracle: Assets.RARI_ORACLE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            ifee: ISSUANCE_FEE,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        f18DaiAdapter = new FAdapter(
            address(divider),
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse adapter

        adapterParams.target = Assets.f18ETH;
        adapterParams.underlying = Assets.WETH;
        f18EthAdapter = new FAdapter(
            address(divider),
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse adapter

        // Create a FAdapter for an underlying token (USDC) with a non-standard number of decimals
        adapterParams.target = Assets.f18USDC;
        adapterParams.underlying = FTokenLike(Assets.f18USDC).underlying();
        f18UsdcAdapter = new FAdapter(
            address(divider),
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse adapter
    }
}

contract FAdapters is FAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetFAdapterScale() public {
        FTokenLike underlying = FTokenLike(Assets.DAI);
        FTokenLike ftoken = FTokenLike(Assets.f18DAI);

        uint256 uDecimals = underlying.decimals();
        // uint256 scale = ftoken.exchangeRateCurrent();
        uint256 scale = ftoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(f18DaiAdapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleLike oracle = PriceOracleLike(Assets.RARI_ORACLE);
        uint256 price = oracle.price(Assets.DAI);
        assertEq(f18DaiAdapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.f18DAI).balanceOf(address(this));

        ERC20(Assets.f18DAI).approve(address(f18DaiAdapter), tBalanceBefore);
        uint256 rate = FTokenLike(Assets.f18DAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        f18DaiAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.f18DAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.f18DAI).balanceOf(address(this));

        ERC20(Assets.DAI).approve(address(f18DaiAdapter), uBalanceBefore);
        uint256 rate = FTokenLike(Assets.f18DAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.DAI).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        f18DaiAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.f18DAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.DAI).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    // test with f18ETH
    function testMainnetFETHAdapterScale() public {
        FTokenLike underlying = FTokenLike(Assets.WETH);
        FTokenLike ftoken = FTokenLike(Assets.f18ETH);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ftoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(f18EthAdapter.scale(), scale);
    }

    function testMainnetFETHGetUnderlyingPrice() public {
        assertEq(f18EthAdapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetFETHUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.f18ETH).balanceOf(address(this));

        ERC20(Assets.f18ETH).approve(address(f18EthAdapter), tBalanceBefore);
        uint256 rate = FTokenLike(Assets.f18ETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        f18EthAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.f18ETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetFETHWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(Assets.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(Assets.f18ETH).balanceOf(address(this));

        ERC20(Assets.WETH).approve(address(f18EthAdapter), uBalanceBefore);
        uint256 rate = FTokenLike(Assets.f18ETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(Assets.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        f18EthAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(Assets.f18ETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(Assets.WETH).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    event ClaimRewards(address indexed owner, uint256 amount);

    function testMainnetNotifyFAdapter() public {
        // At block 14603884, Convex Tribe Pool has 4 rewards distributors with CVX, CRV, LDO and FXS reward tokens
        // asset --> rewards:
        // FRAX3CRV --> CVX and CRV
        // cvxFXSFXS-f --> CVX, CRV and FXS
        // CVX --> no rewards
        // hevm.roll(14603884); // rolling to a previous block makes the .scale() call to fail.

        // f156FRAX3CRV adapter
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: Assets.f156FRAX3CRV,
            underlying: FTokenLike(Assets.f156FRAX3CRV).underlying(),
            oracle: Assets.RARI_ORACLE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: 0,
            maxm: MAX_MATURITY,
            mode: 0,
            ifee: ISSUANCE_FEE,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = Assets.CVX;
        rewardTokens[1] = Assets.CRV;

        address[] memory rewardsDistributosr = new address[](2);
        rewardsDistributosr[0] = Assets.REWARDS_DISTRIBUTOR_CVX;
        rewardsDistributosr[1] = Assets.REWARDS_DISTRIBUTOR_CRV;

        FAdapter f156FRAX3CRVAdapter = new FAdapter(
            address(divider),
            Assets.TRIBE_CONVEX,
            adapterParams,
            rewardTokens,
            rewardsDistributosr
        );
        divider.addAdapter(address(f156FRAX3CRVAdapter));
        divider.setGuard(address(f156FRAX3CRVAdapter), 100e18);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        address prankedAddress = 0x8FdD0CF22012a5FEcDbF77eF30d9e9834DC1bf0A;
        giveTokens(Assets.DAI, 1e18, hevm);
        ERC20(Assets.DAI).approve(address(divider), type(uint256).max);
        divider.initSeries(address(f156FRAX3CRVAdapter), maturity, prankedAddress);

        giveTokens(Assets.f156FRAX3CRV, prankedAddress, 1e18, hevm);

        // Become user with f156FRAX3CRV balance
        hevm.startPrank(prankedAddress);
        ERC20(Assets.f156FRAX3CRV).approve(address(divider), type(uint256).max);
        divider.issue(address(f156FRAX3CRVAdapter), maturity, 1e18);
        hevm.warp(block.timestamp + 3 days);

        // acccrue rewardss
        uint256 accruedCVX = RewardsDistributorLike(Assets.REWARDS_DISTRIBUTOR_CVX).accrue(
            ERC20(Assets.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );
        uint256 accruedCRV = RewardsDistributorLike(Assets.REWARDS_DISTRIBUTOR_CRV).accrue(
            ERC20(Assets.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );
        hevm.stopPrank();

        // Become the divider
        hevm.startPrank(address(divider));

        uint256 ANY = 1337;
        hevm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        hevm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        f156FRAX3CRVAdapter.notify(address(0), 0, true);
    }

    function testMainnet18Decimals() public {
        // Scale is in 18 decimals when the Underlying has 18 decimals (WETH) ----

        // Mint this address some f18ETH & give the adapter approvals (note all cTokens have 8 decimals)
        giveTokens(Assets.f18ETH, ONE_FTOKEN, hevm);
        ERC20(Assets.f18ETH).approve(address(f18EthAdapter), ONE_FTOKEN);

        uint256 wethOut = f18EthAdapter.unwrapTarget(ONE_FTOKEN);
        // WETH is in 18 decimals, so the scale and the "WETH out" from unwrapping a single
        // cToken should be the same
        assertEq(f18EthAdapter.scale(), wethOut);
        // Sanity check
        assertEq(ERC20(Assets.WETH).decimals(), 18);

        // Scale is in 18 decimals when the Underlying has a non-standard number of decimals (6 for USDC) ----

        giveTokens(Assets.f18USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f18USDC).approve(address(f18UsdcAdapter), ONE_FTOKEN);

        uint256 usdcOut = f18UsdcAdapter.unwrapTarget(ONE_FTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((f18UsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(Assets.USDC).decimals(), 6);
    }
}
