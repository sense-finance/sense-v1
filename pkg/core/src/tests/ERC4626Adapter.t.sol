// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockERC4626 } from "@rari-capital/solmate/src/test/utils/mocks/MockERC4626.sol";
import { DSTestPlus } from "@rari-capital/solmate/src/test/utils/DSTestPlus.sol";
import { FixedMath } from "../external/FixedMath.sol";

import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { DSTest } from "./test-helpers/DSTest.sol";
import { ERC4626Adapter } from "../adapters/ERC4626Adapter.sol";
import { Divider, TokenHandler } from "../Divider.sol";

// TODO: test rounding
contract ERC4626AdapterTest is DSTestPlus {
    MockToken public stake;
    MockToken public underlying;
    MockERC4626 public target;

    ERC4626Adapter public erc4626Adapter;
    Divider public divider;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint16 public constant MODE = 0;

    uint256 public constant INITIAL_BALANCE = 1.25e18;

    function setUp() public {
        TokenHandler tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        stake = new MockToken("Mock Stake", "MS", 18);
        underlying = new MockToken("Mock Underlying", "MU", 18);
        target = new MockERC4626(ERC20(address(underlying)), "Mock ERC-4626", "M4626");

        underlying.mint(address(this), INITIAL_BALANCE);

        erc4626Adapter = new ERC4626Adapter(
            address(divider),
            address(target),
            address(0),
            ISSUANCE_FEE,
            address(stake),
            STAKE_SIZE,
            MIN_MATURITY,
            MAX_MATURITY,
            MODE,
            0
        );
    }

    function test4626WrapUnwrap(uint256 wrapAmt) public {
        wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE);

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // 1. Run a full wrap -> unwrap cycle
        uint256 prebal = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap, target.balanceOf(address(this)));
        erc4626Adapter.unwrapTarget(targetFromWrap);
        uint256 postbal = underlying.balanceOf(address(this));

        assertEq(prebal, postbal);

        // 2. Deposit underlying tokens into the vault
        underlying.approve(address(target), INITIAL_BALANCE / 2);
        target.deposit(INITIAL_BALANCE / 4, address(this));
        assertEq(target.totalSupply(), INITIAL_BALANCE / 4);
        assertEq(target.totalAssets(), INITIAL_BALANCE / 4);
        // 3. Init a greater-than-one exchange rate
        target.deposit(INITIAL_BALANCE / 4, address(this));
        assertEq(target.totalSupply(), INITIAL_BALANCE / 2);
        assertEq(target.totalAssets(), INITIAL_BALANCE / 2);
        uint256 targetBalPostDeposit = target.balanceOf(address(this));

        // Bound wrap amount to remaining tokens (tokens not deposited)
        wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE / 2);

        // 4. Run the cycle again now that the vault has some underlying tokens of its own
        prebal = underlying.balanceOf(address(this));
        targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap + targetBalPostDeposit, target.balanceOf(address(this)));
        erc4626Adapter.unwrapTarget(targetFromWrap);
        postbal = underlying.balanceOf(address(this));

        assertEq(prebal, postbal);
    }

    function test4626Scale() public {
        // 1. Deposit initial underlying tokens into the vault
        underlying.approve(address(target), INITIAL_BALANCE / 2);
        target.deposit(INITIAL_BALANCE / 2, address(this));

        // Initializes at 1:1
        assertEq(erc4626Adapter.scale(), 1e18);

        // 2. Vault mutates by +2e18 tokens (simulated yield returned from strategy)
        underlying.mint(address(target), 2e18);

        // 3. Check that the value per share is now higher
        assertGt(erc4626Adapter.scale(), 1e18);
        assertEq(erc4626Adapter.scale(), ((INITIAL_BALANCE / 2 + 2e18) * 1e18) / (INITIAL_BALANCE / 2));
    }

    function test4626ScaleIsExRate() public {
        // 1. Deposit initial underlying tokens into the vault and simulate yield returns
        underlying.approve(address(target), INITIAL_BALANCE / 2);
        target.deposit(INITIAL_BALANCE / 2, address(this));
        underlying.mint(address(target), 2e18);

        // Approval
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // 2. Check that an unwrapped amount reflects scale as an ex rate
        uint256 targetBalPre = target.balanceOf(address(this));
        // Sanity check
        assertGt(targetBalPre, 0);
        // Leave something in the vault
        uint256 underlyingFromUnwrap = erc4626Adapter.unwrapTarget(targetBalPre / 2);
        assertEq(((targetBalPre / 2) * erc4626Adapter.scale()) / 1e18, underlyingFromUnwrap);

        // 3. Check that a wrapped amount reflects scale as an ex rate
        uint256 underlyingBalPre = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(underlyingBalPre / 2);
        assertEq(((underlyingBalPre / 2) * 1e18) / erc4626Adapter.scale(), targetFromWrap);
    }

    // edge case, empties entire vault
}
