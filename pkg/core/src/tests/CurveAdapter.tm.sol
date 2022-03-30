// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { DSTestPlus } from "@rari-capital/solmate/src/test/utils/DSTestPlus.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { Assets } from "./test-helpers/Assets.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { DSTest } from "./test-helpers/DSTest.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";

import { CurveAdapter, CurvePoolLike } from "../adapters/curve/CurveAdapter.sol";
import { Divider, TokenHandler } from "../Divider.sol";

contract CurveAdapterMainnetTest is DSTestPlus, LiquidityHelper {
    MockToken public stake;
    ERC20 public target;
    ERC20 public underlying;

    CurveAdapter public curveAdapter;
    Divider public divider;
    uint256 public coinIndex;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint16 public constant MODE = 0;

    function setUp() public {
        TokenHandler tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        stake = new MockToken("Mock Stake", "MS", 18);

        CurvePoolLike stableSwapPool = CurvePoolLike(Assets.STABLE_SWAP_3_POOL);
        hevm.label(address(stableSwapPool), "StableSwapPool");
        hevm.label(Assets.DAI, "Dai");
        hevm.label(Assets.STABLE_SWAP_3_POOL_LP, "STABLE_SWAP_3_POOL_LP");

        // Search for the Dai token index so that Dai will be the underlying
        for (uint256 i = 0; i < 10; i++) {
            address coin = stableSwapPool.coins(i);
            if (coin == Assets.DAI) {
                coinIndex = i;
                break;
            }
            if (i == 9) {
                revert();
            }
        }

        // Mint 1e18 Dai to this address
        giveTokens(Assets.DAI, 1e18, address(hevm));

        curveAdapter = new CurveAdapter(
            CurvePoolLike(Assets.STABLE_SWAP_3_POOL),
            Assets.STABLE_SWAP_3_POOL_LP,
            coinIndex,
            address(divider),
            address(0),
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0
        );

        underlying = ERC20(curveAdapter.underlying());
        target = ERC20(curveAdapter.target());
    }

    function testCurveAdapterWrapUnwrap() public {
        // wrapAmt = bound(wrapAmt, 1, 1e18);
        uint256 wrapAmt = 1e18;

        // Approvals
        target.approve(address(curveAdapter), type(uint256).max);
        underlying.approve(address(curveAdapter), type(uint256).max);

        // Full cycle
        uint256 prebal = underlying.balanceOf(address(this));
        uint256 wrappedAmt = curveAdapter.wrapUnderlying(wrapAmt);
        // assertEq(wrappedAmt, target.balanceOf(address(this)));
        // curveAdapter.unwrapTarget(wrappedAmt);
        // uint256 postbal = underlying.balanceOf(address(this));

        // assertEq(prebal, postbal);
    }
}