// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Periphery } from "../../Periphery.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { WstETHAdapter, StETHLike, WstETHLike } from "../../adapters/implementations/lido/WstETHAdapter.sol";
import { OwnableWstETHAdapter } from "../../adapters/implementations/lido/OwnableWstETHAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

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

    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRound() external view returns (uint256 round);
}

interface CurveStableSwapLike {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
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

contract WstETHAdapterTestHelper is ForkTest {
    WstETHAdapter internal adapter;
    OwnableWstETHAdapter internal oAdapter;
    Divider internal divider;
    Periphery internal periphery;
    TokenHandler internal tokenHandler;
    Opener public opener;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint48 public constant DEFAULT_LEVEL = 31;
    uint8 public constant DEFAULT_MODE = 0;
    uint64 public constant DEFAULT_TILT = 0;

    function setUp() public {
        fork();

        deal(AddressBook.WETH, address(this), 1e18);
        deal(AddressBook.WSTETH, address(this), 1e18);
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(0),
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
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        ); // wstETH adapter

        adapterParams.mode = 1;
        oAdapter = new OwnableWstETHAdapter(
            address(divider),
            AddressBook.WSTETH,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        ); // Ownable wstETH adapter (for RLVs)
    }

    function sendEther(address to, uint256 amt) external returns (bool) {
        (bool success, ) = to.call{ value: amt }("");
        return success;
    }
}

contract WstETHAdapters is WstETHAdapterTestHelper {
    using FixedMath for uint256;

    function testMainnetWstETHAdapterScale() public {
        uint256 wstETHstETH = StETHLike(AddressBook.STETH).getPooledEthByShares(1 ether);
        assertEq(adapter.scale(), wstETHstETH);
    }

    function testMainnetWstETHAdapterPriceFeedIsValid() public {
        // Check last updated timestamp is less than 1 hour old
        (, int256 stethPrice, , uint256 stethUpdatedAt, ) = PriceOracleLike(adapter.STETH_USD_PRICEFEED())
            .latestRoundData();
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = PriceOracleLike(adapter.ETH_USD_PRICEFEED()).latestRoundData();
        assertTrue(block.timestamp - stethUpdatedAt < 1 hours);
        assertTrue(block.timestamp - ethUpdatedAt < 1 hours);
    }

    function testMainnetGetUnderlyingPrice() public {
        (, int256 stethPrice, , uint256 stethUpdatedAt, ) = PriceOracleLike(adapter.STETH_USD_PRICEFEED())
            .latestRoundData();
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = PriceOracleLike(adapter.ETH_USD_PRICEFEED()).latestRoundData();

        uint256 curvePrice = CurveStableSwapLike(AddressBook.STETH_POOL).get_dy(int128(1), int128(0), 1e18);

        // within 5%
        uint256 stEthEthPrice = uint256(stethPrice).fdiv(uint256(ethPrice));
        assertApproxEqAbs(stEthEthPrice, curvePrice, stEthEthPrice.fmul(0.050e18));
        assertEq(adapter.getUnderlyingPrice(), uint256(stEthEthPrice));
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(this));

        ERC20(AddressBook.WSTETH).approve(address(adapter), tBalanceBefore);
        uint256 rate = StETHLike(AddressBook.STETH).getPooledEthByShares(1 ether);
        uint256 uDecimals = ERC20(AddressBook.STETH).decimals();

        uint256 unwrapped = tBalanceBefore.fmulUp(rate, 10**uDecimals);
        adapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.WSTETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.STETH).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertApproxEqAbs(uBalanceBefore + unwrapped, uBalanceAfter, 100);
    }

    function testMainnetWrapUnderlying() public {
        // get some steth by unwrapping wsteth
        WstETHLike(AddressBook.WSTETH).unwrap(ERC20(AddressBook.WSTETH).balanceOf(address(this)));

        uint256 uBalanceBefore = ERC20(AddressBook.STETH).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(this));

        ERC20(AddressBook.STETH).approve(address(adapter), uBalanceBefore);
        uint256 rate = StETHLike(AddressBook.STETH).getPooledEthByShares(1 ether);
        uint256 uDecimals = ERC20(AddressBook.STETH).decimals();

        uint256 wrapped = adapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.WSTETH).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.STETH).balanceOf(address(this));

        assertApproxEqAbs(uBalanceAfter, 0, 100);
        assertApproxEqAbs(tBalanceBefore + wrapped, tBalanceAfter, 1);
    }

    function testMainnetWrapUnwrap(uint64 wrapAmt) public {
        uint256 prebal = ERC20(AddressBook.STETH).balanceOf(address(this));
        if (wrapAmt > prebal || wrapAmt < 1e4) return;

        // Approvals
        ERC20(AddressBook.STETH).approve(address(adapter), type(uint256).max);
        ERC20(AddressBook.WSTETH).approve(address(adapter), type(uint256).max);

        // Full cycle
        adapter.unwrapTarget(adapter.wrapUnderlying(wrapAmt));
        uint256 postbal = ERC20(AddressBook.STETH).balanceOf(address(this));

        // When wrapping and then unwrapping on Lido we end up with 1 wei less.
        assertApproxEqAbs(prebal, postbal, 1);
    }

    function testOpenSponsorWindow() public {
        vm.warp(1631664000); // 15-09-21 00:00 UTC

        // Add oAdapter to Divider
        divider.setAdapter(address(oAdapter), true);

        uint256 maturity = DateTimeFull.timestampFromDateTime(2021, 10, 4, 0, 0, 0); // Monday
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

        // Opener can open sponsor window
        vm.prank(address(opener));
        vm.expectCall(address(divider), abi.encodeWithSelector(divider.initSeries.selector));
        oAdapter.openSponsorWindow();
    }
}
