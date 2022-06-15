// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { MockERC4626 } from "@rari-capital/solmate/src/test/utils/mocks/MockERC4626.sol";
import { DSTestPlus } from "@rari-capital/solmate/src/test/utils/DSTestPlus.sol";

import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626Adapter } from "../../adapters/abstract/ERC4626Adapter.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { MockOracle } from "../test-helpers/mocks/fuse/MockOracle.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { FixedMath } from "../../external/FixedMath.sol";

// TODO: test rounding
contract ERC4626AdapterTest is DSTestPlus {
    MockToken public stake;
    MockToken public underlying;
    MockERC4626 public target;

    Divider public divider;
    MockOracle internal mockOracle;
    ERC4626Adapter public erc4626Adapter;

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
        mockOracle = new MockOracle();

        stake = new MockToken("Mock Stake", "MS", 18);
        underlying = new MockToken("Mock Underlying", "MU", 18);
        target = new MockERC4626(ERC20(address(underlying)), "Mock ERC-4626", "M4626");

        underlying.mint(address(this), INITIAL_BALANCE);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(mockOracle),
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: Constants.DEFAULT_LEVEL
        });

        erc4626Adapter = new ERC4626Adapter(address(divider), address(target), ISSUANCE_FEE, adapterParams);
    }

    function testWrapUnwrap(uint256 wrapAmt) public {
        wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE);

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // 1. Run a full wrap -> unwrap cycle
        uint256 prebal = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap, target.balanceOf(address(this)));
        assertGt(targetFromWrap, 0);
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
        assertGt(targetFromWrap + targetBalPostDeposit, 0);
        erc4626Adapter.unwrapTarget(targetFromWrap);
        postbal = underlying.balanceOf(address(this));

        assertEq(prebal, postbal);
    }

    function testWrapUnwrapZeroAmt() public {
        uint256 wrapAmt = 0;

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // Trying to wrap 0 underlying should revert
        hevm.expectRevert("ZERO_SHARES");
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);

        // Trying to unwrap 0 target should revert
        hevm.expectRevert("ZERO_ASSETS");
        erc4626Adapter.unwrapTarget(targetFromWrap);
    }

    function testCantWrapMoreThanBalance() public {
        uint256 wrapAmt = INITIAL_BALANCE + 1;

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        hevm.expectRevert("TRANSFER_FROM_FAILED");
        erc4626Adapter.wrapUnderlying(wrapAmt);
    }

    function testCantUnwrapMoreThanBalance(uint256 wrapAmt) public {
        wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE);

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap, target.balanceOf(address(this)));

        bytes memory arithmeticError = abi.encodeWithSignature("Panic(uint256)", 0x11);
        hevm.expectRevert(arithmeticError);
        erc4626Adapter.unwrapTarget(targetFromWrap + 1);
    }

    function testScale() public {
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

    function testScaleIsExRate() public {
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

    /// @notice scale() and scaleStored() have the same implementation
    function testScaleAndScaleStored() public {
        // 1. Deposit initial underlying tokens into the vault
        underlying.approve(address(target), INITIAL_BALANCE / 2);
        target.deposit(INITIAL_BALANCE / 2, address(this));

        // Initializes at 1:1
        assertEq(erc4626Adapter.scale(), 1e18);
        assertEq(erc4626Adapter.scaleStored(), 1e18);

        // 2. Vault mutates by +2e18 tokens (simulated yield returned from strategy)
        underlying.mint(address(target), 2e18);

        // 3. Check that the value per share is now higher
        assertGt(erc4626Adapter.scale(), 1e18);
        assertGt(erc4626Adapter.scaleStored(), 1e18);

        uint256 scale = ((INITIAL_BALANCE / 2 + 2e18) * 1e18) / (INITIAL_BALANCE / 2);
        assertEq(erc4626Adapter.scale(), scale);
        assertEq(erc4626Adapter.scaleStored(), scale);
    }

    function testGetUnderlyingPrice() public {
        assertEq(erc4626Adapter.getUnderlyingPrice(), MockOracle(mockOracle).price(address(underlying)));
    }
}
