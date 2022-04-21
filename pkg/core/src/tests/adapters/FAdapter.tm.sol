// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { FAdapter, PriceOracleLike } from "../../adapters/fuse/FAdapter.sol";
import { CTokenLike } from "../../adapters/compound/CAdapter.sol";
import { BaseAdapter } from "../../adapters/BaseAdapter.sol";

import { Assets } from "../test-helpers/Assets.sol";
import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { User } from "../test-helpers/User.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";

interface RewardsDistributorLike {
    function accrue(ERC20 market, address user) external returns (uint256);
}

contract FAdapterTestHelper is LiquidityHelper, DSTest {
    FAdapter internal f18DaiAdapter; // olympus pool party adapters
    FAdapter internal f18EthAdapter; // olympus pool party adapters
    FAdapter internal f18UsdcAdapter; // olympus pool party adapters
    FAdapter internal f156UsdcAdapter; // tribe convex adapters
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice all cTokens have 8 decimals
    uint256 public constant ONE_FTOKEN = 1e8;
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant INITIAL_BALANCE = 1.25e18;

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

        address target = Assets.f18DAI;
        address underlying = CTokenLike(Assets.f18DAI).underlying();
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
        f18DaiAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            ISSUANCE_FEE,
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 DAI adapter

        target = Assets.f18ETH;
        underlying = Assets.WETH;
        f18EthAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            ISSUANCE_FEE,
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 ETH adapter

        // Create a FAdapter for an underlying token (USDC) with a non-standard number of decimals
        target = Assets.f18USDC;
        underlying = CTokenLike(Assets.f18USDC).underlying();
        f18UsdcAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            ISSUANCE_FEE,
            Assets.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 USDC adapter

        target = Assets.f156USDC;
        underlying = CTokenLike(Assets.f156USDC).underlying();
        f156UsdcAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            ISSUANCE_FEE,
            Assets.TRIBE_CONVEX,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 156 USDC adapter
    }
}

contract FAdapters is FAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetFAdapterScale() public {
        CTokenLike underlying = CTokenLike(Assets.DAI);
        CTokenLike ftoken = CTokenLike(Assets.f18DAI);

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
        uint256 rate = CTokenLike(Assets.f18DAI).exchangeRateCurrent();
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
        uint256 rate = CTokenLike(Assets.f18DAI).exchangeRateCurrent();
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
        CTokenLike underlying = CTokenLike(Assets.WETH);
        CTokenLike ftoken = CTokenLike(Assets.f18ETH);

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
        uint256 rate = CTokenLike(Assets.f18ETH).exchangeRateCurrent();
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
        uint256 rate = CTokenLike(Assets.f18ETH).exchangeRateCurrent();
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
            oracle: Assets.RARI_ORACLE,
            stake: Assets.DAI,
            stakeSize: STAKE_SIZE,
            minm: 0,
            maxm: MAX_MATURITY,
            mode: 0,
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
            Assets.f156FRAX3CRV,
            CTokenLike(Assets.f156FRAX3CRV).underlying(),
            ISSUANCE_FEE,
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

        giveTokens(Assets.DAI, 1e18, hevm);
        ERC20(Assets.DAI).approve(address(divider), type(uint256).max);
        divider.initSeries(address(f156FRAX3CRVAdapter), maturity, address(this));

        giveTokens(Assets.f156FRAX3CRV, address(this), 1e18, hevm);

        // Become user with f156FRAX3CRV balance
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

        // Test with f18USDC
        giveTokens(Assets.f18USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f18USDC).approve(address(f18UsdcAdapter), ONE_FTOKEN);

        uint256 usdcOut = f18UsdcAdapter.unwrapTarget(ONE_FTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((f18UsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(Assets.USDC).decimals(), 6);

        giveTokens(Assets.f18USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f18USDC).approve(address(f18UsdcAdapter), ONE_FTOKEN);

        // Test with f156USDC
        giveTokens(Assets.f18USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f18USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);

        giveTokens(Assets.f156USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f156USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);

        usdcOut = f156UsdcAdapter.unwrapTarget(ONE_FTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((f156UsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(Assets.USDC).decimals(), 6);

        giveTokens(Assets.f156USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f156USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);

        giveTokens(Assets.f156USDC, ONE_FTOKEN, hevm);
        ERC20(Assets.f156USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);
    }

    function testMainnetWrapUnwrap(uint256 wrapAmt) public {
        wrapAmt = fuzzWithBounds(wrapAmt, 1e6, INITIAL_BALANCE);

        giveTokens(Assets.USDC, INITIAL_BALANCE, hevm);

        ERC20 target = ERC20(f18UsdcAdapter.target());
        ERC20 underlying = ERC20(f18UsdcAdapter.underlying());

        // Approvals
        target.approve(address(f18UsdcAdapter), type(uint256).max);
        underlying.approve(address(f18UsdcAdapter), type(uint256).max);

        // 1. Run a full wrap -> unwrap cycle
        uint256 preUnderlyingBal = underlying.balanceOf(address(this));
        uint256 preTargetBal = target.balanceOf(address(this));
        uint256 targetFromWrap = f18UsdcAdapter.wrapUnderlying(wrapAmt);
        assertEq(preTargetBal + targetFromWrap, target.balanceOf(address(this)));
        f18UsdcAdapter.unwrapTarget(targetFromWrap);
        uint256 postUnderlyingBal = underlying.balanceOf(address(this));

        assertClose(preUnderlyingBal, postUnderlyingBal);

        // 2. Deposit underlying tokens into the vault
        uint256 preTargetSupply = target.totalSupply();
        preUnderlyingBal = underlying.balanceOf(address(target));
        underlying.approve(address(target), INITIAL_BALANCE / 2);
        CTokenLike(address(target)).mint(INITIAL_BALANCE / 4);
        assertEq(
            target.totalSupply(),
            preTargetSupply + ((INITIAL_BALANCE / 4).fdiv(CTokenLike(address(target)).exchangeRateCurrent()))
        );
        assertEq(underlying.balanceOf(address(target)), preUnderlyingBal + INITIAL_BALANCE / 4);

        // 3. Init a greater-than-one exchange rate
        preTargetSupply = target.totalSupply();
        preUnderlyingBal = underlying.balanceOf(address(target));
        CTokenLike(address(target)).mint(INITIAL_BALANCE / 4);
        assertEq(
            target.totalSupply(),
            preTargetSupply + ((INITIAL_BALANCE / 4).fdiv(CTokenLike(address(target)).exchangeRateCurrent()))
        );
        assertEq(underlying.balanceOf(address(target)), preUnderlyingBal + INITIAL_BALANCE / 4);

        // Bound wrap amount to remaining tokens (tokens not deposited)
        wrapAmt = fuzzWithBounds(wrapAmt, 1, INITIAL_BALANCE / 2);

        // 4. Run the cycle again now that the vault has some underlying tokens of its own
        uint256 targetBalPostDeposit = target.balanceOf(address(this));
        preUnderlyingBal = underlying.balanceOf(address(this));
        targetFromWrap = f18UsdcAdapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap + targetBalPostDeposit, target.balanceOf(address(this)));
        f18UsdcAdapter.unwrapTarget(targetFromWrap);
        postUnderlyingBal = underlying.balanceOf(address(this));

        assertClose(preUnderlyingBal, postUnderlyingBal);
    }
}
