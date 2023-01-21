// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { FAdapter, PriceOracleLike } from "../../adapters/implementations/fuse/FAdapter.sol";
import { CTokenLike } from "../../adapters/implementations/compound/CAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";

import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

interface RewardsDistributorLike {
    function accrue(ERC20 market, address user) external returns (uint256);
}

contract FAdapterTestHelper is ForkTest {
    FAdapter internal f18DaiAdapter; // olympus pool party adapter
    FAdapter internal f18EthAdapter; // olympus pool party adapter
    FAdapter internal f18UsdcAdapter; // olympus pool party adapter
    FAdapter internal f156UsdcAdapter; // tribe convex adapter
    FAdapter internal f156FRAX3CRVAdapter; // tribe convex adapter
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice all cTokens have 8 decimals
    uint256 public constant ONE_FTOKEN = 1e8;
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant INITIAL_BALANCE = 1.25e18;

    uint8 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    function setUp() public {
        fork();

        // Roll to block mined on Apr 18 2022 at 12:00:10 AM UTC (before Fuse bug)
        vm.rollFork(14605885);

        deal(AddressBook.DAI, address(this), ONE_FTOKEN);
        deal(AddressBook.f18DAI, address(this), ONE_FTOKEN);
        deal(AddressBook.WETH, address(this), ONE_FTOKEN);
        deal(AddressBook.f18ETH, address(this), ONE_FTOKEN);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        address target = AddressBook.f18DAI;
        address underlying = CTokenLike(AddressBook.f18DAI).underlying();
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.RARI_ORACLE,
            stake: AddressBook.DAI,
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
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            AddressBook.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 DAI adapter

        target = AddressBook.f18ETH;
        underlying = AddressBook.WETH;
        f18EthAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            AddressBook.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 ETH adapter

        // Create a FAdapter for an underlying token (USDC) with a non-standard number of decimals
        target = AddressBook.f18USDC;
        underlying = CTokenLike(AddressBook.f18USDC).underlying();
        f18UsdcAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            AddressBook.OLYMPUS_POOL_PARTY,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 18 USDC adapter

        target = AddressBook.f156USDC;
        underlying = CTokenLike(AddressBook.f156USDC).underlying();
        f156UsdcAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            AddressBook.TRIBE_CONVEX,
            adapterParams,
            new address[](0),
            new address[](0)
        ); // Fuse 156 USDC adapter

        // Create adapter with rewards
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = AddressBook.CVX;
        rewardTokens[1] = AddressBook.CRV;

        address[] memory rewardsDistributors = new address[](2);
        rewardsDistributors[0] = AddressBook.REWARDS_DISTRIBUTOR_CVX;
        rewardsDistributors[1] = AddressBook.REWARDS_DISTRIBUTOR_CRV;

        target = AddressBook.f156FRAX3CRV;
        underlying = CTokenLike(AddressBook.f156FRAX3CRV).underlying();
        adapterParams.minm = 0;
        f156FRAX3CRVAdapter = new FAdapter(
            address(divider),
            target,
            underlying,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            AddressBook.TRIBE_CONVEX,
            adapterParams,
            rewardTokens,
            rewardsDistributors
        ); // Fuse 156 FRAX3CRV adapter
    }
}

contract FAdapters is FAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetFAdapterScale() public {
        CTokenLike underlying = CTokenLike(AddressBook.DAI);
        CTokenLike ftoken = CTokenLike(AddressBook.f18DAI);

        uint256 uDecimals = underlying.decimals();
        // uint256 scale = ftoken.exchangeRateCurrent();
        uint256 scale = ftoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(f18DaiAdapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleLike oracle = PriceOracleLike(AddressBook.RARI_ORACLE);
        uint256 price = oracle.price(AddressBook.DAI);
        assertEq(f18DaiAdapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.f18DAI).balanceOf(address(this));

        ERC20(AddressBook.f18DAI).approve(address(f18DaiAdapter), tBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.f18DAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.DAI).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        f18DaiAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.f18DAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.DAI).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.f18DAI).balanceOf(address(this));

        ERC20(AddressBook.DAI).approve(address(f18DaiAdapter), uBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.f18DAI).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.DAI).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        f18DaiAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.f18DAI).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.DAI).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }

    // test with f18ETH
    function testMainnetFETHAdapterScale() public {
        CTokenLike underlying = CTokenLike(AddressBook.WETH);
        CTokenLike ftoken = CTokenLike(AddressBook.f18ETH);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = ftoken.exchangeRateCurrent() / 10**(uDecimals - 8);
        assertEq(f18EthAdapter.scale(), scale);
    }

    function testMainnetFETHGetUnderlyingPrice() public {
        assertEq(f18EthAdapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetFETHUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.f18ETH).balanceOf(address(this));

        ERC20(AddressBook.f18ETH).approve(address(f18EthAdapter), tBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.f18ETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.WETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        f18EthAdapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.f18ETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetFETHWrapUnderlying() public {
        uint256 uBalanceBefore = ERC20(AddressBook.WETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.f18ETH).balanceOf(address(this));

        ERC20(AddressBook.WETH).approve(address(f18EthAdapter), uBalanceBefore);
        uint256 rate = CTokenLike(AddressBook.f18ETH).exchangeRateCurrent();
        uint256 uDecimals = ERC20(AddressBook.WETH).decimals();

        uint256 wrapped = uBalanceBefore.fdiv(rate, 10**uDecimals);
        f18EthAdapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.f18ETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.WETH).balanceOf(address(this));

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

        deal(AddressBook.DAI, address(this), 1e18);
        ERC20(AddressBook.DAI).approve(address(divider), type(uint256).max);
        divider.initSeries(address(f156FRAX3CRVAdapter), maturity, address(this));

        deal(AddressBook.f156FRAX3CRV, address(this), 1e18);
        ERC20(AddressBook.f156FRAX3CRV).approve(address(divider), type(uint256).max);
        divider.issue(address(f156FRAX3CRVAdapter), maturity, 1e18);
        vm.warp(block.timestamp + 3 days);

        // acccrue rewardss
        uint256 accruedCVX = RewardsDistributorLike(AddressBook.REWARDS_DISTRIBUTOR_CVX).accrue(
            ERC20(AddressBook.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );
        uint256 accruedCRV = RewardsDistributorLike(AddressBook.REWARDS_DISTRIBUTOR_CRV).accrue(
            ERC20(AddressBook.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );

        // Become the divider
        vm.startPrank(address(divider));

        uint256 ANY = 1337;
        vm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        vm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        f156FRAX3CRVAdapter.notify(address(0), 0, true);
    }

    function testFailMainnetSkipClaimRewardIfAlreadyCalled() public {
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

        deal(AddressBook.DAI, address(this), 1e18);
        ERC20(AddressBook.DAI).approve(address(divider), type(uint256).max);
        divider.initSeries(address(f156FRAX3CRVAdapter), maturity, address(this));

        deal(AddressBook.f156FRAX3CRV, address(this), 1e18);
        ERC20(AddressBook.f156FRAX3CRV).approve(address(divider), type(uint256).max);
        divider.issue(address(f156FRAX3CRVAdapter), maturity, 1e18);
        vm.warp(block.timestamp + 3 days);

        // acccrue rewardss
        uint256 accruedCVX = RewardsDistributorLike(AddressBook.REWARDS_DISTRIBUTOR_CVX).accrue(
            ERC20(AddressBook.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );
        uint256 accruedCRV = RewardsDistributorLike(AddressBook.REWARDS_DISTRIBUTOR_CRV).accrue(
            ERC20(AddressBook.f156FRAX3CRV),
            address(f156FRAX3CRVAdapter)
        );

        // Become the divider
        vm.startPrank(address(divider));

        uint256 ANY = 1337;

        // Expect a f156FRAX3CRVAdapter ClaimRewards event when notifying
        vm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        f156FRAX3CRVAdapter.notify(address(0), 0, true);

        // Should fail to expect a f156FRAX3CRVAdapter ClaimRewards event when notifying again in the same block
        vm.expectEmit(true, false, false, false);
        emit ClaimRewards(address(f156FRAX3CRVAdapter), ANY);

        f156FRAX3CRVAdapter.notify(address(0), 0, true);
    }

    function testMainnet18Decimals() public {
        // Scale is in 18 decimals when the Underlying has 18 decimals (WETH) ----

        // Mint this address some f18ETH & give the adapter approvals (note all cTokens have 8 decimals)
        deal(AddressBook.f18ETH, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f18ETH).approve(address(f18EthAdapter), ONE_FTOKEN);

        uint256 wethOut = f18EthAdapter.unwrapTarget(ONE_FTOKEN);
        // WETH is in 18 decimals, so the scale and the "WETH out" from unwrapping a single
        // cToken should be the same
        assertEq(f18EthAdapter.scale(), wethOut);
        // Sanity check
        assertEq(ERC20(AddressBook.WETH).decimals(), 18);

        // Scale is in 18 decimals when the Underlying has a non-standard number of decimals (6 for USDC) ----

        // Test with f18USDC
        deal(AddressBook.f18USDC, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f18USDC).approve(address(f18UsdcAdapter), ONE_FTOKEN);

        uint256 usdcOut = f18UsdcAdapter.unwrapTarget(ONE_FTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((f18UsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(AddressBook.USDC).decimals(), 6);

        deal(AddressBook.f18USDC, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f18USDC).approve(address(f18UsdcAdapter), ONE_FTOKEN);

        // Test with f156USDC
        deal(AddressBook.f18USDC, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f18USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);

        deal(AddressBook.f156USDC, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f156USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);

        usdcOut = f156UsdcAdapter.unwrapTarget(ONE_FTOKEN);
        // USDC is in 6 decimals, so the scale should be equal to the "USDC out"
        // scaled up to 18 decimals (after we strip the extra precision off)
        assertEq((f156UsdcAdapter.scale() / 1e12) * 1e12, usdcOut * 10**(18 - 6));
        // Sanity check
        assertEq(ERC20(AddressBook.USDC).decimals(), 6);

        deal(AddressBook.f156USDC, address(this), ONE_FTOKEN);
        ERC20(AddressBook.f156USDC).approve(address(f156UsdcAdapter), ONE_FTOKEN);
    }

    // function testMainnetWrapUnwrap(uint256 wrapAmt) public {
    //     wrapAmt = bound(wrapAmt, 1e6, INITIAL_BALANCE);

    //     deal(AddressBook.USDC, address(this), INITIAL_BALANCE);

    //     ERC20 target = ERC20(f18UsdcAdapter.target());
    //     ERC20 underlying = ERC20(f18UsdcAdapter.underlying());

    //     // Approvals
    //     target.approve(address(f18UsdcAdapter), type(uint256).max);
    //     underlying.approve(address(f18UsdcAdapter), type(uint256).max);

    //     // 1. Run a full wrap -> unwrap cycle
    //     uint256 preUnderlyingBal = underlying.balanceOf(address(this));
    //     uint256 preTargetBal = target.balanceOf(address(this));
    //     uint256 targetFromWrap = f18UsdcAdapter.wrapUnderlying(wrapAmt);
    //     assertEq(preTargetBal + targetFromWrap, target.balanceOf(address(this)));
    //     f18UsdcAdapter.unwrapTarget(targetFromWrap);
    //     uint256 postUnderlyingBal = underlying.balanceOf(address(this));

    //     assertApproxEqAbs(preUnderlyingBal, postUnderlyingBal, 100);

    //     // 2. Deposit underlying tokens into the vault
    //     uint256 preTargetSupply = target.totalSupply();
    //     preUnderlyingBal = underlying.balanceOf(address(target));
    //     underlying.approve(address(target), INITIAL_BALANCE / 2);
    //     CTokenLike(address(target)).mint(INITIAL_BALANCE / 4);
    //     assertEq(
    //         target.totalSupply(),
    //         preTargetSupply + ((INITIAL_BALANCE / 4).fdiv(CTokenLike(address(target)).exchangeRateCurrent()))
    //     );
    //     assertEq(underlying.balanceOf(address(target)), preUnderlyingBal + INITIAL_BALANCE / 4);

    //     // 3. Init a greater-than-one exchange rate
    //     preTargetSupply = target.totalSupply();
    //     preUnderlyingBal = underlying.balanceOf(address(target));
    //     CTokenLike(address(target)).mint(INITIAL_BALANCE / 4);
    //     assertEq(
    //         target.totalSupply(),
    //         preTargetSupply + ((INITIAL_BALANCE / 4).fdiv(CTokenLike(address(target)).exchangeRateCurrent()))
    //     );
    //     assertEq(underlying.balanceOf(address(target)), preUnderlyingBal + INITIAL_BALANCE / 4);

    //     // Bound wrap amount to remaining tokens (tokens not deposited)
    //     wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE / 2);

    //     // 4. Run the cycle again now that the vault has some underlying tokens of its own
    //     uint256 targetBalPostDeposit = target.balanceOf(address(this));
    //     preUnderlyingBal = underlying.balanceOf(address(this));
    //     targetFromWrap = f18UsdcAdapter.wrapUnderlying(wrapAmt);
    //     assertEq(targetFromWrap + targetBalPostDeposit, target.balanceOf(address(this)));
    //     f18UsdcAdapter.unwrapTarget(targetFromWrap);
    //     postUnderlyingBal = underlying.balanceOf(address(this));

    //     assertApproxEqAbs(preUnderlyingBal, postUnderlyingBal, 100);
    // }

    event RewardTokensChanged(address[] indexed rewardTokens);
    event RewardsDistributorsChanged(address[] indexed rewardsDistributorsList);

    function testMainnetSetRewardsTokens() public {
        address[] memory rewardTokens = new address[](5);
        rewardTokens[0] = AddressBook.LDO;
        rewardTokens[1] = AddressBook.FXS;

        address[] memory rewardsDistributors = new address[](5);
        rewardsDistributors[0] = AddressBook.REWARDS_DISTRIBUTOR_LDO;
        rewardsDistributors[1] = AddressBook.REWARDS_DISTRIBUTOR_FXS;

        vm.expectEmit(true, false, false, false);
        emit RewardTokensChanged(rewardTokens);

        vm.expectEmit(true, false, false, false);
        emit RewardsDistributorsChanged(rewardsDistributors);

        f156FRAX3CRVAdapter.setRewardTokens(rewardTokens, rewardsDistributors);

        assertEq(f156FRAX3CRVAdapter.rewardTokens(0), AddressBook.LDO);
        assertEq(f156FRAX3CRVAdapter.rewardTokens(1), AddressBook.FXS);
        assertEq(f156FRAX3CRVAdapter.rewardsDistributorsList(AddressBook.LDO), AddressBook.REWARDS_DISTRIBUTOR_LDO);
        assertEq(f156FRAX3CRVAdapter.rewardsDistributorsList(AddressBook.FXS), AddressBook.REWARDS_DISTRIBUTOR_FXS);
    }

    function testFuzzMainnetCantSetRewardsTokens(address lad) public {
        if (lad == address(this)) return;
        address[] memory rewardTokens = new address[](2);
        address[] memory rewardsDistributors = new address[](2);
        vm.expectRevert("UNTRUSTED");
        vm.prank(address(0x1234567890123456789012345678901234567890));
        f156FRAX3CRVAdapter.setRewardTokens(rewardTokens, rewardsDistributors);
    }
}
