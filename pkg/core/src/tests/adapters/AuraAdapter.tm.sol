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
import { AutoRoller, OwnedAdapterLike } from "@auto-roller/src/AutoRoller.sol";
import { AutoRollerFactory } from "@auto-roller/src/AutoRollerFactory.sol";

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

interface Authentication {
    function getActionId(bytes4) external returns (bytes32);

    function grantRole(bytes32, address) external;
}

interface ProtocolFeesController {
    function setSwapFeePercentage(uint256) external;
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

    AutoRollerFactory public constant rlvFactory = AutoRollerFactory(0x3B0f35bDD6Da9e3b8513c58Af8Fdf231f60232E5);

    function setUp() public {
        fork();
        vm.rollFork(16869769); // Mar-20-2023 03:26:59 PM +UTC

        aToken = AddressBook.AURA_B_RETH_STABLE_VAULT;
        address poolBaseAsset = AddressBook.WETH;
        underlying = ERC20(poolBaseAsset);
        target = new AuraVaultWrapper(ERC20(underlying), ERC4626(aToken));
        balancerVault = BalancerVault(address(target.balancerVault()));
        divider = Divider(AddressBook.DIVIDER_1_2_0);

        vm.prank(AddressBook.SENSE_MULTISIG);
        divider.setPeriphery(address(this));

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

        oAdapter = new OwnableAuraAdapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            0,
            adapterParams,
            rewardTokens
        ); // Ownable aToken adapter (for RLVs)

        _setAdapter(address(oAdapter));

        // Set rlvFactory as trusted on oAdapter so the factory can set RLV as trusted in oAdapter
        oAdapter.setIsTrusted(address(rlvFactory), true);

        // Set protocol fees
        ProtocolFeesController protocolFeesCollector = ProtocolFeesController(balancerVault.getProtocolFeesCollector());
        Authentication authorizer = Authentication(balancerVault.getAuthorizer());
        bytes32 actionId = Authentication(address(protocolFeesCollector)).getActionId(
            protocolFeesCollector.setSwapFeePercentage.selector
        );
        vm.prank(0x10A19e7eE7d7F8a52822f6817de8ea18204F2e4f);
        authorizer.grantRole(actionId, address(this));
        protocolFeesCollector.setSwapFeePercentage(0);
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
        vm.prank(divider.periphery());
        (pt, yt) = divider.initSeries(address(adapter), maturity, msg.sender);
    }

    function _setAdapter(address _adapter) internal {
        // add adapter to Divider
        vm.prank(divider.periphery());
        divider.addAdapter(_adapter);

        // set guarded false
        vm.prank(AddressBook.SENSE_MULTISIG);
        divider.setGuarded(false);
    }

    function _issue(
        address _adapter,
        uint256 _maturity,
        address _from,
        uint256 _amt
    ) internal returns (uint256 issued) {
        vm.startPrank(_from);
        // issue `_amt`
        target.approve(address(divider), _amt);
        issued = divider.issue(_adapter, _maturity, _amt);
        vm.stopPrank();

        // we use the getRate from the BPT to calculate how many PTs and YTs have been issued
        assertEq(issued, _amt.fmul(_getRate()));

        assertGt(ERC20(divider.pt(_adapter, _maturity)).balanceOf(_from), 0);
        assertGt(ERC20(divider.yt(_adapter, _maturity)).balanceOf(_from), 0);
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

    function _increaseScale(uint64 swapSize) internal {
        // increase scale (BPT price) by doing a swap
        address from = address(0x123);
        vm.startPrank(from);
        deal(address(underlying), from, swapSize);
        address RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        BalancerPool pool = BalancerPool(address(target.aToken().asset()));
        _balancerSwap(address(underlying), RETH, swapSize, pool.getPoolId(), 0, payable(from));
        vm.stopPrank();
    }
}

contract AuraAdapters is AuraAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetAuraAdapterScale() public {
        uint256 aTokenUnderlying = _getRate();
        assertEq(adapter.scale(), aTokenUnderlying);
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
        vm.assume(wrapAmt > 1e10);

        deal(address(underlying), address(this), wrapAmt);
        uint256 prebal = underlying.balanceOf(address(this));

        // Approvals
        underlying.approve(address(adapter), type(uint256).max);
        target.approve(address(adapter), type(uint256).max);

        // Full cycle
        adapter.unwrapTarget(adapter.wrapUnderlying(wrapAmt));

        uint256 postbal = underlying.balanceOf(address(this));

        // NOTE: we can't expect that prebal == postbal because when we do a `wrapUnderlying` we are
        // doing a pool join which modifies the pool price (hence, modifies the scale value).
        // So, when we then do an `unwrapTarget` the scale would be different.
        // For this test, we assert that they are approx equal (within 0.1%) and we assume
        // wrapAmt to be > 1e10
        assertApproxEqAbs(prebal, postbal, prebal.fmul(0.0010e18));
    }

    function testMainnetCanCollectRewards(uint64 uBal, uint64 swapSize) public {
        vm.assume(uBal > 1e10);
        vm.assume(swapSize > 1e4);

        // get target (w-auraB-RETH-stable-vault) by wrapping underlying (WETH)
        deal(address(underlying), address(this), uBal);
        underlying.approve(address(adapter), uBal);
        uint256 tBal = adapter.wrapUnderlying(uBal);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();
        _issue(address(adapter), maturity, address(this), tBal);

        uint256 scale = adapter.scale(); // current scale

        // roll to period finish
        vm.warp(IRewards(address(target.aToken())).periodFinish() + 100);

        // distribute rewards
        uint256 AURA_PID = 15; // 15 is the aura PID
        IBooster(AddressBook.AURA_BOOSTER).earmarkRewards(AURA_PID);

        _increaseScale(swapSize);

        uint256 auraBalBefore = ERC20(AddressBook.AURA).balanceOf(address(this));
        uint256 balBalBefore = ERC20(AddressBook.BAL).balanceOf(address(this));

        // collect
        YT yt = YT(divider.yt(address(adapter), maturity));
        uint256 uBal = yt.balanceOf(address(this));
        uint256 tBalNow = uBal.fdivUp(adapter.scale());
        uint256 tBalPrev = uBal.fdiv(scale);
        uint256 collected = tBalPrev > tBalNow ? tBalPrev - tBalNow : 0;
        assertEq(yt.collect(), collected);
        console.log("Collecting %s target", collected);

        assertGt(ERC20(AddressBook.AURA).balanceOf(address(this)), auraBalBefore);
        assertGt(ERC20(AddressBook.BAL).balanceOf(address(this)), balBalBefore);
    }

    function testMainnetCanCollectRewardsProportionally(uint256 tBal, uint64 swapSize) public {
        vm.assume(tBal > 1e10);
        vm.assume(tBal < type(uint64).max);
        vm.assume(swapSize > 1e4);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();

        address bpt = address(target.pool());

        // load Alice with some target by wrapping BPT tokens (B-RETH-stable-vault)
        uint256 amt = (60 * tBal) / 100;
        deal(bpt, address(this), amt);
        ERC20(bpt).approve(address(target), amt);
        target.depositFromBPT(amt, address(this));

        // alice issues
        _issue(address(adapter), maturity, address(this), amt);

        vm.startPrank(address(0xfede));
        // load 0xfede with some target by wrapping BPT tokens (B-RETH-stable-vault)
        amt = (40 * tBal) / 100;
        deal(bpt, address(0xfede), amt);
        ERC20(bpt).approve(address(target), amt);
        target.depositFromBPT(amt, address(0xfede));
        vm.stopPrank();

        // 0xfede issues
        _issue(address(adapter), maturity, address(0xfede), amt);

        // roll to period finish
        vm.warp(IRewards(address(target.aToken())).periodFinish() + 100);

        // increase scale and distribute rewards
        _increaseScale(swapSize);

        uint256 AURA_PID = 15; // 15 is the aura PID
        vm.prank(address(0x2)); // this address will receive a reward for calling `earmarkRewards`
        IBooster(AddressBook.AURA_BOOSTER).earmarkRewards(AURA_PID);

        // force rewards distribution to adapter
        vm.prank(address(0x1));
        divider.issue(address(adapter), maturity, 0);

        // check adapter rewards balances
        uint256 adapterAuraBal = ERC20(AddressBook.AURA).balanceOf(address(adapter));
        uint256 adapterBalBal = ERC20(AddressBook.BAL).balanceOf(address(adapter));

        YT yt = YT(divider.yt(address(adapter), maturity));

        // collect for alice
        yt.collect();

        // collect for 0xfede
        vm.prank(address(0xfede));
        yt.collect();

        // check rewards were distributed proportionally
        assertApproxEqAbs(ERC20(AddressBook.AURA).balanceOf(address(this)), (60 * adapterAuraBal) / 100, 1);
        assertApproxEqAbs(ERC20(AddressBook.BAL).balanceOf(address(this)), (60 * adapterBalBal) / 100, 1);
        assertApproxEqAbs(ERC20(AddressBook.AURA).balanceOf(address(0xfede)), (40 * adapterAuraBal) / 100, 1);
        assertApproxEqAbs(ERC20(AddressBook.BAL).balanceOf(address(0xfede)), (40 * adapterBalBal) / 100, 1);

        // assert adapter has no more rewards
        assertApproxEqAbs(ERC20(AddressBook.AURA).balanceOf(address(adapter)), 0, 2);
        assertApproxEqAbs(ERC20(AddressBook.BAL).balanceOf(address(adapter)), 0, 2);
    }

    function testMainnetCombine(uint64 uBal, uint64 swapSize) public {
        vm.assume(uBal > 1e10);
        vm.assume(swapSize > 1e4);

        // get target (w-auraB-RETH-stable-vault) by wrapping underlying (WETH)
        deal(address(underlying), address(this), uBal);
        underlying.approve(address(adapter), uBal);
        uint256 tBalToIssue = adapter.wrapUnderlying(uBal);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();
        uint256 issued = _issue(address(adapter), maturity, address(this), tBalToIssue);

        // roll to period finish
        vm.warp(IRewards(address(target.aToken())).periodFinish() + 100);

        _increaseScale(swapSize);

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
        vm.prank(divider.periphery());
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidMaturity.selector));
        divider.initSeries(address(oAdapter), maturity, msg.sender);

        // Mint some stake to sponsor Series
        deal(AddressBook.DAI, divider.periphery(), STAKE_SIZE);

        // Periphery approves divider to pull stake to sponsor series
        vm.prank(divider.periphery());
        ERC20(AddressBook.DAI).approve(address(divider), STAKE_SIZE);

        // Opener can open sponsor window
        vm.prank(address(opener));
        vm.expectCall(address(divider), abi.encodeWithSelector(divider.initSeries.selector));
        oAdapter.openSponsorWindow();
    }

    function testMainnetRoll(uint64 tBal) public {
        uint256 tDecimals = target.decimals();
        uint256 rollAmt = 10**(tDecimals - 2); // amount needed for rolling (0.01 target)
        vm.assume(tBal > rollAmt);

        // create RLV
        AutoRoller rlv = rlvFactory.create(OwnedAdapterLike(address(oAdapter)), address(0xfede), 3); // target duration
        vm.prank(AddressBook.SENSE_MULTISIG);
        divider.setPeriphery(AddressBook.PERIPHERY_1_4_0);

        (address t, address s, uint256 sSize) = oAdapter.getStakeAndTarget();

        // load wallet
        deal(s, address(this), sSize);
        deal(t, address(this), tBal); // 1 target for deposit + 0.1 target for roll

        // approve RLV to pull target
        target.approve(address(rlv), type(uint64).max);

        // approve RLV to pull stake
        ERC20 stake = ERC20(s);
        stake.approve(address(rlv), sSize);

        // roll 1st series
        rlv.roll();
        console.log("- First series sucessfully rolled!");

        // check we can deposit
        rlv.deposit(tBal - rollAmt, address(this)); // deposit all target balance except 0.1 (used for rolling))
        console.log("- target sucessfully deposited!");
    }

    function testMainnetDepositWithdrawFromToBPT(uint64 bptAmt) public {
        vm.assume(bptAmt > 0);
        bptAmt = 10e18;

        // load wallet with BPTs
        deal(AddressBook.B_RETH_STABLE, address(this), bptAmt);

        // approve target to pull BPTs
        ERC20(AddressBook.B_RETH_STABLE).approve(address(target), bptAmt);

        // deposit from BPTs (converts BPTs into wrapped token)
        vm.expectEmit(true, true, true, true);
        emit DepositFromBPT(address(this), address(this), bptAmt);

        target.depositFromBPT(bptAmt, address(this));
        assertEq(target.balanceOf(address(this)), bptAmt);
        assertEq(ERC20(AddressBook.B_RETH_STABLE).balanceOf(address(this)), 0);
        assertEq(ERC20(AddressBook.AURA_B_RETH_STABLE_VAULT).balanceOf(address(target)), bptAmt);

        // sponsor series and issue
        (, , uint256 maturity) = _sponsorSeries();
        uint256 issued = _issue(address(adapter), maturity, address(this), bptAmt);

        // combine
        uint256 combined = divider.combine(address(adapter), maturity, issued);
        uint256 tBal = target.balanceOf(address(this));
        assertApproxEqAbs(bptAmt, combined, 2);
        assertApproxEqAbs(bptAmt, tBal, 2);

        // withdraw to BPTs (converts wrapped token into BPTs)
        vm.expectEmit(true, true, true, true);
        emit WithdrawToBPT(address(this), address(this), address(this), tBal);

        target.withdrawToBPT(tBal, address(this), address(this));
        assertEq(target.balanceOf(address(this)), 0);
        assertEq(ERC20(AddressBook.B_RETH_STABLE).balanceOf(address(this)), tBal);
    }

    event DepositFromBPT(address indexed sender, address indexed receiver, uint256 indexed amount);
    event WithdrawToBPT(address indexed sender, address indexed receiver, address owner, uint256 indexed amount);
}
