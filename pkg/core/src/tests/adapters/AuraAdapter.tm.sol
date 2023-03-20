// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { BalancerPool } from "../../external/balancer/Pool.sol";
import { BalancerVault, IAsset } from "../../external/balancer/Vault.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { FixedMath } from "../../external/FixedMath.sol";
import { RateProvider } from "../../external/balancer/RateProvider.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { AuraAdapter } from "../../adapters/implementations/aura/AuraAdapter.sol";
import { AuraVaultWrapper } from "../../adapters/implementations/aura/AuraVaultWrapper.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Periphery } from "../../Periphery.sol";
import { YT } from "../../tokens/YT.sol";
import { OwnableAuraAdapter } from "../../adapters/implementations/aura/OwnableAuraAdapter.sol";

// Test references
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";

import "hardhat/console.sol";

// AURA: HOW YIELD WORKS?
// In terms of how yields work, you really have to think about the underlying mechanisms to understand.
// Basically, each day AURA pools get harvested (by arbers who get a small portion of the fees).
// When harvested, all the unclaimed BAL is claimed, AURA is minted based on claimed BAL (aura minted per
// bal formula on docs), fees are taken for auraBAL.
// The remaining rewards are then built into a queue(or buffer) that pays out the earned BAL + minted
// aura less fees over a 7 day period at an even rate per block.
// This means that the current yield on AURA is made up of 1/7th of each of the last 7 days of deposits.
// If everyone deposits on day 0, and no one deposits or withdraws for 7 days, than the projected and
// actual yields should match.  If more capital has left the pool than joined over the last 7 days,
// the current yield should be above projected, and if capital is joining the pool every day,
// the current will remain below the projected until inflows taper off.

interface PriceOracleLike {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IBooster {
    function earmarkRewards(uint256 _pid) external returns (bool);
}

interface IRewards {
    function periodFinish() external view returns (uint256);
}

contract Opener is ForkTest {
    Divider public divider;
    uint256 public maturity;
    address public adapter;

    constructor(
        Divider _divider,
        uint256 _maturity,
        address _adapter
    ) {
        divider = _divider;
        maturity = _maturity;
        adapter = _adapter;
    }

    function onSponsorWindowOpened(address, uint256) external {
        vm.prank(divider.periphery()); // impersonate Periphery
        divider.initSeries(adapter, maturity, msg.sender);
    }
}

contract AuraAdapterTestHelper is ForkTest {
    using FixedMath for uint256;

    AuraAdapter internal adapter;
    OwnableAuraAdapter internal oAdapter;
    Divider internal divider;
    Periphery internal periphery;
    TokenHandler internal tokenHandler;
    Opener public opener;

    ERC20 public underlying;
    AuraVaultWrapper public target;
    BalancerVault public balancerVault;
    address public aToken;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint48 public constant DEFAULT_LEVEL = 31;
    uint8 public constant DEFAULT_MODE = 0;
    uint64 public constant DEFAULT_TILT = 0;

    function setUp() public {
        fork();

        aToken = AddressBook.AURA_B_RETH_STABLE_VAULT;
        address poolBaseAsset = AddressBook.WETH;
        underlying = ERC20(poolBaseAsset);
        target = new AuraVaultWrapper(ERC20(underlying), ERC4626(aToken));
        balancerVault = BalancerVault(address(target.balancerVault()));

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.ETH_USD_PRICEFEED, // Chainlink ETH-USD price feed
            stake: AddressBook.DAI,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: DEFAULT_MODE,
            tilt: DEFAULT_TILT,
            level: DEFAULT_LEVEL
        });

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = AddressBook.AURA;
        rewardTokens[1] = AddressBook.BAL;

        adapter = new AuraAdapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            0,
            adapterParams,
            rewardTokens
        ); // aToken adapter

        // we set Sense Multisig as trusted so we can set the adapter as a rewardsReceipient
        target.setIsTrusted(AddressBook.SENSE_MULTISIG, true);

        // we unset the deployer as trusted from target
        target.setIsTrusted(address(this), false);

        // set adapter as rewards recipient
        vm.prank(AddressBook.SENSE_MULTISIG);
        target.setRewardsRecipient(address(adapter));

        _setAdapter(address(adapter));

        adapterParams.mode = 1;
        oAdapter = new OwnableAuraAdapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            0,
            adapterParams,
            rewardTokens
        ); // Ownable aToken adapter (for RLVs)

        _setAdapter(address(oAdapter));
    }

    function _sponsorSeries()
        internal
        returns (
            address pt,
            address yt,
            uint256 maturity
        )
    {
        // calculate maturity
        maturity = DateTimeFull.timestampFromDateTime(2023, 5, 1, 0, 0, 0); // Monday

        // mint stake to sponsor Series
        deal(AddressBook.DAI, address(this), STAKE_SIZE);

        // sponsor series
        ERC20(AddressBook.DAI).approve(address(divider), STAKE_SIZE);
        (pt, yt) = divider.initSeries(address(adapter), maturity, msg.sender);
    }

    function _setAdapter(address adapter) internal {
        // add adapter to Divider
        vm.prank(divider.periphery());
        divider.addAdapter(adapter);

        // set guard
        divider.setGuard(adapter, 100e18);
    }

    function _issue(
        address _adapter,
        uint256 _maturity,
        uint256 _amt
    ) internal returns (uint256 issued) {
        // issue `_amt`
        target.approve(address(divider), _amt);
        issued = divider.issue(_adapter, _maturity, _amt);

        // we use the getRate from the BPT to calculate how many PTs and YTs have been issued
        assertEq(issued, _amt.fmul(_getRate()));

        assertGt(ERC20(divider.pt(_adapter, _maturity)).balanceOf(address(this)), 0);
        assertGt(ERC20(divider.pt(_adapter, _maturity)).balanceOf(address(this)), 0);
    }

    function _getRate() internal view returns (uint256) {
        return RateProvider(address(target.pool())).getRate();
    }

    function _balancerSwap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 poolId,
        uint256 minAccepted,
        address payable receiver
    ) internal returns (uint256 amountOut) {
        // approve vault to spend tokenIn
        ERC20(assetIn).approve(address(balancerVault), amountIn);

        BalancerVault.SingleSwap memory request = BalancerVault.SingleSwap({
            poolId: poolId,
            kind: BalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amountIn,
            userData: hex""
        });

        BalancerVault.FundManagement memory funds = BalancerVault.FundManagement({
            sender: receiver,
            fromInternalBalance: false,
            recipient: receiver,
            toInternalBalance: false
        });

        amountOut = balancerVault.swap(request, funds, minAccepted, type(uint256).max);
    }

    function _increaseScale() internal {
        // increase scale (BPT price) by doing a swap
        vm.startPrank(address(0xfede));
        deal(address(underlying), address(0xfede), 100e18);
        address RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        BalancerPool pool = BalancerPool(address(target.aToken().asset()));
        _balancerSwap(address(underlying), RETH, 100e18, pool.getPoolId(), 0, payable(address(0xfede)));
        vm.stopPrank();
    }
}

contract AuraAdapters is AuraAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetAuraAdapterScale() public {
        uint256 aTokenUnderlying = _getRate();
        assertEq(adapter.scale(), aTokenUnderlying);
    }

    function testMainnetAuraAdapterPriceFeedIsValid() public {
        // Check last updated timestamp is less than 1 hour old
        (address oracle, , , , , , , ) = adapter.adapterParams();
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = PriceOracleLike(oracle).latestRoundData(); // ETH:USD
        assertTrue(block.timestamp - ethUpdatedAt < 1 hours);
    }

    function testMainnetGetUnderlyingPrice() public {
        assertEq(adapter.getUnderlyingPrice(), 1e18);
    }

    function testMainnetUnwrapTarget() public {
        deal(address(underlying), address(this), 1e18);

        // deposit underlying (BPT) to get some target (w-auraB-RETH-stable-vault)
        underlying.approve(address(target), 1e18);
        uint256 deposit = target.deposit(1e18, address(this));

        // assert that the wrapper now has a balance of auraB-RETH-stable-vault
        // which should be the same as the deposit (since 1:1)
        assertEq(target.aToken().balanceOf(address(target)), deposit);

        // unwrap target (will return WETH)
        uint256 uBalanceBefore = underlying.balanceOf(address(this));
        uint256 tBalanceBefore = target.balanceOf(address(this));

        target.approve(address(adapter), tBalanceBefore);

        uint256 expectedUnwrapped = target.convertToAssets(tBalanceBefore);
        uint256 unwrapped = adapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = target.balanceOf(address(this));
        uint256 uBalanceAfter = underlying.balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
        assertEq(expectedUnwrapped, unwrapped);

        // assert wrapper has NO auraB-RETH-stable-vault balance
        assertEq(target.aToken().balanceOf(address(target)), 0);
    }

    function testMainnetWrapUnderlying() public {
        deal(address(underlying), address(this), 1e18);

        uint256 uBalanceBefore = underlying.balanceOf(address(this));
        uint256 tBalanceBefore = target.balanceOf(address(this));

        underlying.approve(address(adapter), uBalanceBefore);

        uint256 expectedWrapped = target.convertToShares(uBalanceBefore);
        uint256 wrapped = adapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = target.balanceOf(address(this));
        uint256 uBalanceAfter = underlying.balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);

        assertEq(expectedWrapped, wrapped);

        // assert wrapper has a balance of auraB-RETH-stable-vault
        assertEq(target.aToken().balanceOf(address(target)), expectedWrapped);
    }

    function testMainnetWrapUnwrap(uint64 wrapAmt) public {
        if (wrapAmt < 1e4) return;

        deal(address(underlying), address(this), wrapAmt);
        uint256 prebal = underlying.balanceOf(address(this));

        // Approvals
        underlying.approve(address(adapter), type(uint256).max);
        target.approve(address(adapter), type(uint256).max);

        // Full cycle
        adapter.unwrapTarget(adapter.wrapUnderlying(wrapAmt));
        uint256 postbal = underlying.balanceOf(address(this));

        // TODO: if ran independently, it passes, if ran with the whole suite, it fails
        assertEq(prebal, postbal);
    }

    function testMainnetCanCollectRewards() public {
        // get target (w-auraB-RETH-stable-vault) by wrapping underlying (WETH)
        deal(address(underlying), address(this), 1e18);
        underlying.approve(address(adapter), 1e18);
        uint256 tBal = adapter.wrapUnderlying(1e18);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();
        _issue(address(adapter), maturity, tBal);

        uint256 scale = adapter.scale(); // current scale

        // roll to period finish
        vm.warp(IRewards(address(target.aToken())).periodFinish() + 100);

        // distribute rewards (TODO: I think this is only for BAL rewards, not AURA)
        uint256 POOL_ID = 15; // 15 is the pool ID
        IBooster(AddressBook.AURA_BOOSTER).earmarkRewards(POOL_ID);

        _increaseScale();

        uint256 auraBalBefore = ERC20(AddressBook.AURA).balanceOf(address(this));
        uint256 balBalBefore = ERC20(AddressBook.BAL).balanceOf(address(this));

        // collect
        YT yt = YT(divider.yt(address(adapter), maturity));
        uint256 uBal = yt.balanceOf(address(this));
        uint256 tBalNow = uBal.fdivUp(adapter.scale());
        uint256 tBalPrev = uBal.fdiv(scale);
        assertEq(yt.collect(), tBalPrev - tBalNow);

        assertGt(ERC20(AddressBook.AURA).balanceOf(address(this)), auraBalBefore);
        assertGt(ERC20(AddressBook.BAL).balanceOf(address(this)), balBalBefore);
    }

    function testMainnetCombine() public {
        // get target (w-auraB-RETH-stable-vault) by wrapping underlying (WETH)
        deal(address(underlying), address(this), 1e18);
        underlying.approve(address(adapter), 1e18);
        uint256 tBalToIssue = adapter.wrapUnderlying(1e18);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();
        uint256 issued = _issue(address(adapter), maturity, tBalToIssue);

        // roll to period finish
        vm.warp(IRewards(address(target.aToken())).periodFinish() + 100);

        _increaseScale();

        // combine
        uint256 combined = divider.combine(address(adapter), maturity, issued);
        uint256 tBal = target.balanceOf(address(this));
        assertApproxEqAbs(tBalToIssue, combined, 2);
        assertApproxEqAbs(tBalToIssue, tBal, 2);
    }

    function testOpenSponsorWindow() public {
        uint256 maturity = DateTimeFull.timestampFromDateTime(2023, 5, 1, 0, 0, 0); // Monday
        opener = new Opener(divider, maturity, address(oAdapter));

        // Add Opener as trusted address on ownable adapter
        oAdapter.setIsTrusted(address(opener), true);

        vm.prank(address(0xfede));
        vm.expectRevert("UNTRUSTED");
        oAdapter.openSponsorWindow();

        // No one can sponsor series directly using Divider (even if it's the Periphery)
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        divider.initSeries(address(oAdapter), maturity, msg.sender);

        // Mint some stake to sponsor Series
        deal(AddressBook.DAI, divider.periphery(), STAKE_SIZE);

        // Periphery approves divider to pull stake to sponsor series
        vm.prank(divider.periphery());
        ERC20(AddressBook.DAI).approve(address(divider), STAKE_SIZE);

        // Open can open sponsor window
        vm.prank(address(opener));
        vm.expectCall(address(divider), abi.encodeWithSelector(divider.initSeries.selector));
        oAdapter.openSponsorWindow();
    }
}
