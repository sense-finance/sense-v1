// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { MockERC4626 } from "@rari-capital/solmate/src/test/utils/mocks/MockERC4626.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol"; // TODO: replace for RWRAPPER
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider, TokenHandler } from "../../Divider.sol";
import { RAdapter, WETHLike, RTokenLike } from "../../adapters/implementations/ribbon/RAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";

import { AddressBook } from "../test-helpers/AddressBook.sol";
import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";

interface RTokenLikePlus is RTokenLike {
    function rollToNextOption() external;

    function keeper() external returns (address);

    function commitAndClose() external;

    function currentOption() external returns (address);

    function setManagementFee(uint256 newManagementFee) external;

    function setPerformanceFee(uint256 newPeformanceFee) external;

    function owner() external returns (address);

    // function depositReceipts() external returns (DepositReceipt memory receipt);
    function depositReceipts(address)
        external
        returns (
            uint16 round,
            uint104 amount,
            uint128 unredeemedShares
        );

    function totalBalance() external returns (uint256);

    function optionAuctionID() external returns (uint256);

    function GNOSIS_EASY_AUCTION() external returns (address);

    struct DepositReceipt {
        // Maximum of 65535 rounds. Assuming 1 round is 7 days, maximum is 1256 years.
        uint16 round;
        // Deposit amount, max 20,282,409,603,651 or 20 trillion ETH deposit
        uint104 amount;
        // Unredeemed shares balance
        uint128 unredeemedShares;
    }
}

interface OptionLike {
    function expiryTimestamp() external returns (uint256);
}

interface EasyAuction {
    function settleAuction(uint256 auctionId) external returns (bytes32 clearingOrder);

    function auctionData(uint256 auctionId)
        external
        returns (
            address,
            address,
            uint256,
            uint256,
            bytes32,
            uint256,
            uint256,
            bytes32,
            bytes32,
            uint96,
            bool,
            bool,
            uint256,
            uint256
        );
}

interface PriceOracleLike {
    function setAssetPricer(address _asset, address _pricer) external;

    function owner() external returns (address);

    function setExpiryPrice(
        address _asset,
        uint256 _expiryTimestamp,
        uint256 _price
    ) external;

    function getPrice(address _asset) external view returns (uint256);

    function getPricer(address _asset) external view returns (address);

    function setLockingPeriod(address _pricer, uint256 _lockingPeriod) external;

    function setDisputePeriod(address _pricer, uint256 _disputePeriod) external;
}

interface StETHLike {
    /// @notice Get amount of stETH for a one wstETH
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    function submit(address _referral) external payable returns (uint256);
}

contract RAdapterTestHelper is LiquidityHelper, DSTest {
    RAdapter internal rstETHAdapter; // Ribbon stETH Theta Adapter
    RAdapter internal rBTCAdapter; // Ribbon wBTC Theta Adapter
    Divider internal divider;
    TokenHandler internal tokenHandler;

    /// @notice rTokens take the decimals of the underlying
    uint256 public constant ONE_RTOKEN = 1e18;
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant INITIAL_BALANCE = 1.25e18;

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        giveTokens(AddressBook.STETH, 100e18 + 1, hevm);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        MockToken target = new MockToken(
            "wrstETH-THETA",
            "Wrapped stETH Theta Vault",
            ERC20(AddressBook.RSTETH_THETA).decimals()
        );
        MockToken target2 = new MockToken(
            "wrstETH-THETA2",
            "Wrapped stETH Theta Vault 2",
            ERC20(AddressBook.RSTETH_THETA).decimals()
        );
        (, , address asset, address underlying, , ) = RTokenLike(AddressBook.RSTETH_THETA).vaultParams();
        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.OPYN_ORACLE,
            stake: AddressBook.WETH,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        rstETHAdapter = new RAdapter(
            address(divider),
            address(target),
            address(target2),
            // asset, // TODO: or use underlying var from vaultParams?
            AddressBook.STETH, // TODO: where to get the underlying??
            AddressBook.RSTETH_THETA,
            ISSUANCE_FEE,
            adapterParams
        ); // Ribbon stETH Theta adapter

        // Ribbon without fees
        hevm.startPrank(RTokenLikePlus(rstETHAdapter.rToken()).owner());
        RTokenLikePlus(rstETHAdapter.rToken()).setManagementFee(0);
        RTokenLikePlus(rstETHAdapter.rToken()).setPerformanceFee(0);
        hevm.stopPrank();

        (, , asset, underlying, , ) = RTokenLike(AddressBook.RBTC_THETA).vaultParams();
        rBTCAdapter = new RAdapter(
            address(divider),
            AddressBook.RBTC_THETA,
            AddressBook.RBTC_THETA,
            asset,
            AddressBook.RBTC_THETA,
            ISSUANCE_FEE,
            adapterParams
        ); // Ribbon BTC adapter
    }
}

contract RAdapters is RAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetRAdapterScale() public {
        // rstETH scale
        RTokenLike underlying = RTokenLike(AddressBook.WETH);
        RTokenLike rtoken = RTokenLike(AddressBook.RSTETH_THETA);

        uint256 uDecimals = underlying.decimals();
        uint256 scale = rtoken.pricePerShare() / 10**(uDecimals - 8);
        assertEq(rstETHAdapter.scale(), scale);

        // rBTC scale
        underlying = RTokenLike(AddressBook.WBTC);
        rtoken = RTokenLike(AddressBook.RBTC_THETA);

        uDecimals = underlying.decimals();
        scale = rtoken.pricePerShare() / 10**(uDecimals - 8);
        assertEq(rBTCAdapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        PriceOracleLike oracle = PriceOracleLike(AddressBook.OPYN_ORACLE);
        uint256 price = oracle.getPrice(AddressBook.WBTC);
        assertEq(rBTCAdapter.getUnderlyingPrice(), price);
    }

    function testMainnetCantUnwrapTargetIfNotInitiated() public {
        ERC20(AddressBook.RSTETH_THETA).approve(address(rstETHAdapter), type(uint256).max);
        hevm.expectRevert("Not initiated");
        rstETHAdapter.unwrapTarget(1e18);
    }

    function testMainnetUnwrapTarget() public {
        ERC20 wTarget = ERC20(rstETHAdapter.target());
        ERC20 w2Target = ERC20(rstETHAdapter.target2());
        ERC20 target = ERC20(rstETHAdapter.rToken());
        ERC20 underlying = ERC20(AddressBook.STETH);

        // User has no wrapped target
        assertEq(0, wTarget.balanceOf(address(this)));

        // Approve adapter to pull user's underlying
        ERC20(AddressBook.STETH).approve(address(rstETHAdapter), type(uint256).max);

        // Wrap underlying
        uint256 uBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(this));
        uint256 wrappedAmt = rstETHAdapter.wrapUnderlying(uBalanceBefore);

        // Wrapped target balance should be equal to underlying / price per share
        uint256 wtBalanceBefore = wTarget.balanceOf(address(this));
        uint256 pps = RTokenLike(AddressBook.RSTETH_THETA).pricePerShare();
        assertEq(wtBalanceBefore, uBalanceBefore.fdiv(pps));
        assertEq(wtBalanceBefore, wrappedAmt);

        // Perform some actions on Opyn so as to be able to close the current round
        // and start the next one
        closeRound();

        // Initiate withdrawal (will pull user's target)
        wTarget.approve(address(rstETHAdapter), wtBalanceBefore);
        rstETHAdapter.initiateUnwrapTarget(wtBalanceBefore);
        assertEq(wTarget.balanceOf(msg.sender), 0);
        // assert totalSupply decreased
        // assert totalSupply of wtarget 2 increased

        uint256 wtBalanceAfter = wTarget.balanceOf(address(this));
        assertEq(wtBalanceAfter, 0);

        closeRound();

        uint256 wt2BalanceBefore = w2Target.balanceOf(address(this));
        uint256 unwrappedAmt = rstETHAdapter.unwrapTarget(wt2BalanceBefore);
        uint256 wt2BalanceAfter = w2Target.balanceOf(address(this));
        assertEq(wt2BalanceAfter, 0);

        uint256 uBalanceAfter = underlying.balanceOf(address(this));
        assertEq(uBalanceAfter, unwrappedAmt);
        // assertEq(uBalanceBefore + unwrapped, uBalanceAfter); // TODO: assert
    }

    // Test case: adapter has target form other user deposits from active rounds.
    // Alice makes a new deposits and tries withdrawing before her deposit got into
    // the next round. This should NOT trigger an initiate withdraw on Ribbon.
    // In the example above:
    // - 1st user makes a deposit of 100 steth
    // - round is closed
    // - Alice makes a deposit of 100 steth
    // - Alice tries initiating a withdrawal
    // `initiateUnwrapTarget` is triggering an instant withdraw (which is fine)
    // because the available underlying is enough to cover the withdrawal amount of Alice.
    // But, somehow, we are sending back to Alice a bit less than the underlying she deposited.
    // TODO: we need to understand why
    function testMainnetUnwrapTargetWhenWrappedTargetNotReachedRound() public {
        ERC20 wTarget = ERC20(rstETHAdapter.target());
        ERC20 w2Target = ERC20(rstETHAdapter.target2());
        ERC20 target = ERC20(rstETHAdapter.rToken());
        ERC20 underlying = ERC20(AddressBook.STETH);

        // Wrap underlying (STETH)
        uint256 pps = RTokenLike(AddressBook.RSTETH_THETA).roundPricePerShare(38);
        uint256 uBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(this));
        ERC20(AddressBook.STETH).approve(address(rstETHAdapter), uBalanceBefore);
        rstETHAdapter.wrapUnderlying(uBalanceBefore);

        closeRound();

        // Fund Alice wallet with underlying
        hevm.label(address(123), "Alice");
        giveTokens(AddressBook.STETH, address(123), 100e18 + 1, hevm);

        // Prank Alice on next calls
        hevm.startPrank(address(123));

        // Alice wraps underlying (on the new round)
        uBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(123));
        ERC20(AddressBook.STETH).approve(address(rstETHAdapter), uBalanceBefore);
        uint256 wtBal = rstETHAdapter.wrapUnderlying(uBalanceBefore);
        RTokenLike(AddressBook.RSTETH_THETA).pricePerShare();

        // Alice initiates a withdrawal (note that she didn't wait for the round to start)
        // so the instantWithdraw should have been triggered
        wTarget.approve(address(rstETHAdapter), wtBal);
        rstETHAdapter.initiateUnwrapTarget(wtBal, pps);

        hevm.stopPrank();

        // FIXME
        assertEq(uBalanceBefore, ERC20(AddressBook.STETH).balanceOf(address(123)));
    }

    // Perform some actions on Ribbon and Opyn so as to be able to close the current round
    // and start the next one
    function closeRound() internal {
        // Set expiry prices on Opyn for the relevant assets involved (WETH, WSTETH)
        OptionLike option = OptionLike(RTokenLikePlus(AddressBook.RSTETH_THETA).currentOption());
        uint256 expiryTimestamp = option.expiryTimestamp();
        PriceOracleLike oracle = PriceOracleLike(AddressBook.OPYN_ORACLE); // Or get from option.controller().getConfiguration() 2nd param

        uint256 wethPrice = oracle.getPrice(AddressBook.WETH);
        address wethPricer = oracle.getPricer(AddressBook.WETH); // underlyingAsset pricer

        uint256 wstEthPrice = oracle.getPrice(AddressBook.WSTETH);
        address wstEthPricer = oracle.getPricer(AddressBook.WSTETH); // collateralAsset pricer

        // Set pricers locking and dispute periods to 0
        hevm.startPrank(oracle.owner());
        oracle.setLockingPeriod(wethPricer, 0);
        oracle.setDisputePeriod(wethPricer, 0);
        oracle.setLockingPeriod(wstEthPricer, 0);
        oracle.setDisputePeriod(wstEthPricer, 0);
        hevm.stopPrank();

        // Fast forward to expiry date (Friday 8am UTC)
        hevm.warp(expiryTimestamp + 1);

        // Set WETH and WSTETH prices for the expiry date
        hevm.prank(wethPricer);
        // https://etherscan.io/tx/0x05ec31825a6247cace4086dac3ee01b7c49d0d722c873c19a2b46a86413005dd
        // oracle.setExpiryPrice(AddressBook.WETH, expiryTimestamp, 1659081600);
        oracle.setExpiryPrice(AddressBook.WETH, expiryTimestamp, wethPrice);
        hevm.prank(wstEthPricer);
        // https://etherscan.io/tx/0xe840a801fa9d77de448dd5d06193306be0b745eb68472eef7be45f0a77acfcc6
        // oracle.setExpiryPrice(AddressBook.WSTETH, expiryTimestamp, 1659081600);
        oracle.setExpiryPrice(AddressBook.WSTETH, expiryTimestamp, wstEthPrice);

        // Commit and close
        hevm.warp(expiryTimestamp + 2);
        // https://etherscan.io/tx/0xeac31cf639fc217e384da2cc9ae10962594f4a56a7cc356a4b38977d0a1cae5e
        RTokenLikePlus(AddressBook.RSTETH_THETA).commitAndClose();

        // Impersonate keeper so we can call `rollToNextOption` to close this current round
        hevm.prank(RTokenLikePlus(AddressBook.RSTETH_THETA).keeper());
        // https://etherscan.io/tx/0x9ff72095d4c4152d329fb8924e6c3fafcb3027991f5be605c229f019b4c55808
        RTokenLikePlus(AddressBook.RSTETH_THETA).rollToNextOption();

        // uint256 optionAuctionId = RTokenLikePlus(AddressBook.RSTETH_THETA).optionAuctionID();
        // address easyAuction = RTokenLikePlus(AddressBook.RSTETH_THETA).GNOSIS_EASY_AUCTION();
        // get EasyAuction from RTokenLikePlus
        // EasyAuction(easyAuction).auctionData(optionAuctionId);
        // EasyAuction(easyAuction).settleAuction(optionAuctionId);
    }
}
