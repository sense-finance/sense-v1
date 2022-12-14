// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { MockERC4626 } from "../test-helpers/mocks/MockERC4626.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

import { ChainlinkPriceOracle, FeedRegistryLike } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { FixedMath } from "../../external/FixedMath.sol";

contract MockOracle is IPriceFeed {
    function price(address) external view returns (uint256 price) {
        return 555e18;
    }
}

contract ERC4626AdapterTest is Test {
    using FixedMath for uint256;

    MockToken public stake;
    MockToken public underlying;
    MockERC4626 public target;
    MasterPriceOracle public masterOracle;
    ChainlinkPriceOracle public chainlinkOracle;

    Divider public divider;
    ERC4626Adapter public erc4626Adapter;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint8 public constant MODE = 0;

    uint256 public constant INITIAL_BALANCE = 1.25e18;

    function setUp() public {
        TokenHandler tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        // Deploy Chainlink price oracle
        chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master oracle
        address[] memory data;
        masterOracle = new MasterPriceOracle(address(chainlinkOracle), data, data);

        stake = new MockToken("Mock Stake", "MS", 18);
        underlying = new MockToken("Mock Underlying", "MU", 18);
        target = new MockERC4626(ERC20(address(underlying)), "Mock ERC-4626", "M4626", ERC20(underlying).decimals());

        underlying.mint(address(this), INITIAL_BALANCE);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(masterOracle),
            stake: address(stake),
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0,
            level: Constants.DEFAULT_LEVEL
        });

        erc4626Adapter = new ERC4626Adapter(
            address(divider),
            address(target),
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        );
    }

    function testCantWrapMoreThanBalance() public {
        uint256 wrapAmt = INITIAL_BALANCE + 1;

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        erc4626Adapter.wrapUnderlying(wrapAmt);
    }

    function testCantUnwrapMoreThanBalance(uint256 wrapAmt) public {
        wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE);

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertEq(targetFromWrap, target.balanceOf(address(this)));

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        erc4626Adapter.unwrapTarget(targetFromWrap + 1);
    }

    function testWrapUnwrapZeroAmt() public {
        uint256 wrapAmt = 0;

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // Trying to wrap 0 underlying should revert
        vm.expectRevert("ZERO_SHARES");
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);

        // Trying to unwrap 0 target should revert
        vm.expectRevert("ZERO_ASSETS");
        erc4626Adapter.unwrapTarget(targetFromWrap);
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

    function testGetUnderlyingPriceUsingSenseChainlinkOracle() public {
        // Mock call to Rari's master oracle
        uint256 price = 123e18;
        bytes memory data = abi.encode(price); // return data
        vm.mockCall(
            address(chainlinkOracle),
            abi.encodeWithSelector(chainlinkOracle.price.selector, address(underlying)),
            data
        );

        assertEq(erc4626Adapter.getUnderlyingPrice(), price);
    }

    function testGetUnderlyingPriceRevertsIfZero() public {
        // Mock call to Rari's master oracle
        uint256 price = 0;
        bytes memory data = abi.encode(price); // return data
        vm.mockCall(
            address(chainlinkOracle),
            abi.encodeWithSelector(chainlinkOracle.price.selector, address(underlying)),
            data
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidPrice.selector));
        erc4626Adapter.getUnderlyingPrice();
    }

    // Oracle-related tests

    function testGetUnderlyingPriceCustomOracle() public {
        // Deploy a custom oracle
        MockOracle oracle = new MockOracle();
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle);

        // Add oracle to Sense master price oracle
        masterOracle.add(underlyings, oracles);

        uint256 price = MockOracle(oracle).price(address(underlying));
        assertEq(erc4626Adapter.getUnderlyingPrice(), price);
    }

    function testShouldAlwaysDefaultToCustom() public {
        // Mock call to Chainlink's registry
        uint256 price = 123e18;
        bytes memory data = abi.encode(price); // return datat

        IPriceFeed oracle = IPriceFeed(AddressBook.RARI_ORACLE);
        vm.mockCall(
            address(AddressBook.RARI_ORACLE),
            abi.encodeWithSelector(oracle.price.selector, address(underlying)),
            data
        );

        // Deploy a custom oracle
        MockOracle customOracle = new MockOracle();
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(customOracle);

        // Add oracle to Sense master price oracle
        masterOracle.add(underlyings, oracles);

        // Assert that the price returned is the one from the custom oracle and not the one Rari
        assertEq(erc4626Adapter.getUnderlyingPrice(), customOracle.price(address(underlying)));
    }

    // function testCantGetUnderlyingPriceIfNoFeed() public {
    // }
}
