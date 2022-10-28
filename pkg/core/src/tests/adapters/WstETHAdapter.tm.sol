// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Periphery } from "../../Periphery.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { WstETHAdapter, StETHLike, WstETHLike } from "../../adapters/implementations/lido/WstETHAdapter.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { AddressBook } from "../test-helpers/AddressBook.sol";
import { MockFactory } from "../test-helpers/mocks/MockFactory.sol";
import { DateTimeFull } from "../test-helpers/DateTimeFull.sol";
import { Constants } from "../test-helpers/Constants.sol";

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

contract WstETHAdapterTestHelper is Test {
    WstETHAdapter internal adapter;
    Divider internal divider;
    Periphery internal periphery;
    TokenHandler internal tokenHandler;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint48 public constant DEFAULT_LEVEL = 31;
    uint8 public constant DEFAULT_MODE = 0;
    uint64 public constant DEFAULT_TILT = 0;

    function setUp() public {
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
}
