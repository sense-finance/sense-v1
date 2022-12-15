// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";

import { FixedMath } from "../../external/FixedMath.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { Periphery } from "../../Periphery.sol";

import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { MockOracle } from "../test-helpers/mocks/fuse/MockOracle.sol";
import { Constants } from "../test-helpers/Constants.sol";

/// Mainnet tests
/// @dev reads from ENV the target address or defaults to imUSD 4626 token if none
/// @dev reads from ENV an address of a user with underlying balance. This is used in case tha
/// the `deal()` fails at finding the storage slot for the vault.
contract ERC4626Adapters is Test {
    using FixedMath for uint256;

    ERC20 public underlying;
    ERC4626 public target;
    ERC4626Adapter public erc4626Adapter;
    address public userWithAssets; // address of a userr with underlying balance
    uint256 public delta;

    function setUp() public {
        try vm.envAddress("ERC4626_ADDRESS") returns (address vault) {
            target = ERC4626(vault);
            console.log("Running tests for token: ", target.symbol());
        } catch {
            target = ERC4626(AddressBook.IMUSD);
        }
        underlying = ERC20(target.asset());

        // set `userWithAssets` if exists
        try vm.envAddress("USER_WITH_ASSETS") returns (address user) {
            userWithAssets = user;
        } catch {}

        if (address(underlying) == AddressBook.MUSD) {
            // Add Rari mStable oracle to Sense Oracle
            address[] memory underlyings = new address[](1);
            underlyings[0] = address(underlying);

            address[] memory oracles = new address[](1);
            oracles[0] = AddressBook.RARI_MSTABLE_ORACLE;
            vm.prank(AddressBook.SENSE_MULTISIG);
            MasterPriceOracle(AddressBook.SENSE_MASTER_ORACLE).add(underlyings, oracles);
        }

        // Add some balance of underlying to this contract
        if (userWithAssets == address(0)) {
            deal(address(underlying), address(this), 10 * 10**underlying.decimals());
        } else {
            uint256 underlyingBalance = underlying.balanceOf(userWithAssets);
            vm.prank(userWithAssets);
            underlying.transfer(address(this), underlyingBalance);
        }

        if (address(underlying) == AddressBook.STETH) delta = 1;

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.SENSE_MASTER_ORACLE,
            stake: AddressBook.WETH,
            stakeSize: Constants.DEFAULT_STAKE_SIZE,
            minm: Constants.DEFAULT_MIN_MATURITY,
            maxm: Constants.DEFAULT_MAX_MATURITY,
            mode: Constants.DEFAULT_MODE,
            tilt: Constants.DEFAULT_TILT,
            level: Constants.DEFAULT_LEVEL
        });
        erc4626Adapter = new ERC4626Adapter(
            AddressBook.DIVIDER_1_2_0,
            address(target),
            AddressBook.SENSE_MULTISIG,
            Constants.DEFAULT_ISSUANCE_FEE,
            adapterParams
        ); // ERC-4626 adapter

        // Approvals
        target.approve(address(erc4626Adapter), type(uint256).max);
        underlying.approve(address(erc4626Adapter), type(uint256).max);

        // Onboard adapter
        vm.prank(AddressBook.SENSE_MULTISIG);
        Periphery(AddressBook.PERIPHERY_1_4_0).onboardAdapter(address(erc4626Adapter), true);
    }

    function testMainnetCantWrapMoreThanBalance() public {
        uint256 balance = underlying.balanceOf(address(this));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        if (address(underlying) == AddressBook.STETH) {
            // Lido's 1 wei corner case: https://docs.lido.fi/guides/steth-integration-guide#1-wei-corner-case
            erc4626Adapter.wrapUnderlying(balance + 2);
        } else {
            erc4626Adapter.wrapUnderlying(balance + 1);
        }
    }

    function testMainnetCantUnwrapMoreThanBalance() public {
        uint256 wrappedTarget = erc4626Adapter.wrapUnderlying(underlying.balanceOf(address(this)));
        assertEq(wrappedTarget, target.balanceOf(address(this)));

        vm.expectRevert();
        erc4626Adapter.unwrapTarget(wrappedTarget + 1);
    }

    // Not all ERC4626 implementations enforce this and it's not enforced by the standard
    // function testMainnetWrapUnwrapZeroAmt() public {
    //     vm.expectRevert();
    //     erc4626Adapter.wrapUnderlying(0);

    //     vm.expectRevert();
    //     erc4626Adapter.unwrapTarget(0);
    // }

    function testMainnetWrapUnwrap(uint256 wrapAmt) public {
        // Trigger a deposit so if there's a pending yield it will collect and the exchange rate gets updated
        underlying.approve(address(target), 1);
        target.deposit(1, address(this));

        // Run a full wrap -> unwrap cycle

        // 1. Wrap
        uint256 prebal = underlying.balanceOf(address(this));
        wrapAmt = bound(wrapAmt, 1, prebal);
        uint256 targetPrebal = target.balanceOf(address(this));
        uint256 assetPrebal = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertGt(targetFromWrap, 0);

        assertApproxEqAbs(underlying.balanceOf(address(this)), assetPrebal - wrapAmt, delta);
        assertApproxEqAbs(target.balanceOf(address(this)), targetPrebal + targetFromWrap, delta);

        // some protocols will revert if doing two actions on the same block (e.g deposit followed by withdraw)
        vm.roll(block.number + 1);

        // 2. unwrap
        erc4626Adapter.unwrapTarget(targetFromWrap);
        uint256 postbal = underlying.balanceOf(address(this));

        assertApproxEqAbs(prebal, postbal, delta);
    }

    function testMainnetScale() public {
        uint256 decimals = target.decimals();
        uint256 scale = target.convertToAssets(10**decimals) * 10**(18 - decimals);
        assertEq(erc4626Adapter.scale(), scale);
    }

    // function testScale() public {
    //     // 1. Deposit initial underlying tokens into the target
    //     underlying.approve(address(target), INITIAL_BALANCE / 2);
    //     target.deposit(INITIAL_BALANCE / 2, address(this));

    //     // Initializes at 1:1
    //     assertEq(erc4626Adapter.scale(), 1e18);

    //     // 2. Vault mutates by +2e18 tokens (simulated yield returned from strategy)
    //     underlying.mint(address(target), 2e18);

    //     // 3. Check that the value per share is now higher
    //     assertGt(erc4626Adapter.scale(), 1e18);
    //     assertEq(erc4626Adapter.scale(), ((INITIAL_BALANCE / 2 + 2e18) * 1e18) / (INITIAL_BALANCE / 2));
    // }

    function testScaleIsExRate() public {
        // 1. Deposit initial underlying tokens into the target and simulate yield returns
        uint256 underlyingBalance = underlying.balanceOf(address(this));
        underlying.approve(address(target), underlyingBalance / 2);
        target.deposit(underlyingBalance / 2, address(this));

        // some protocols will revert if doing two actions on the same block (e.g deposit followed by withdraw)
        vm.roll(block.number + 1);

        // 2. Check that an unwrapped amount reflects scale as an ex rate
        uint256 targetPrebal = target.balanceOf(address(this));
        // Sanity check
        assertGt(targetPrebal, 0);
        // Leave something in the target
        uint256 underlyingFromUnwrap = erc4626Adapter.unwrapTarget(targetPrebal / 2);
        assertApproxEqAbs(((targetPrebal / 2) * erc4626Adapter.scale()) / 1e18, underlyingFromUnwrap, delta);

        vm.roll(block.number + 1);

        // 3. Check that a wrapped amount reflects scale as an ex rate
        uint256 underlyingBalPre = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(underlyingBalPre / 2);
        assertApproxEqAbs(((underlyingBalPre / 2) * 1e18) / erc4626Adapter.scale(), targetFromWrap, 1);
    }

    /// @notice scale() and scaleStored() have the same implementation
    /// @dev given the fact that totalAssets() might be implemented differently by each protocol,
    /// this test may fail and we cannot generalise it
    // function testScaleAndScaleStored() public {
    //     // // 1. Deposit initial underlying tokens into the target
    //     uint256 underlyingBalance = target.totalAssets();
    //     uint256 scale = erc4626Adapter.scale();
    //     uint256 scaleStored = erc4626Adapter.scaleStored();

    //     // 1. Vault mutates by +2e18 tokens (simulated yield returned from strategy)
    //     uint256 uAmt = 2 * 10 ** underlying.decimals();
    //     deal(address(underlying), address(0xfede), uAmt);
    //     vm.prank(address(0xfede));
    //     underlying.transfer(address(target), uAmt);

    //     // 2. Check that the value per share is now higher
    //     assertGt(erc4626Adapter.scale(), scale);
    //     assertGt(erc4626Adapter.scaleStored(), scaleStored);

    //     scale = ((underlyingBalance + uAmt) * 1e18) / (underlyingBalance);
    //     assertEq(erc4626Adapter.scale(), scale);
    //     assertEq(erc4626Adapter.scaleStored(), scale);
    // }

    function testMainnetGetUnderlyingPrice() public {
        // Since the MasterPriceOracle uses Rari's master oracle, the prices should match
        uint256 price = IPriceFeed(AddressBook.RARI_ORACLE).price(address(underlying));
        assertEq(erc4626Adapter.getUnderlyingPrice(), price);
    }

    function testMainnetGetUnderlyingPriceWhenCustomOracle() public {
        // Deploy a custom oracle
        MockOracle oracle = new MockOracle();
        address[] memory underlyings = new address[](1);
        underlyings[0] = address(underlying);
        address[] memory oracles = new address[](1);
        oracles[0] = address(oracle);

        // Add oracle to Sense master price oracle
        vm.prank(AddressBook.SENSE_MULTISIG);
        MasterPriceOracle(AddressBook.SENSE_MASTER_ORACLE).add(underlyings, oracles);

        uint256 price = oracle.price(address(underlying));
        assertEq(erc4626Adapter.getUnderlyingPrice(), price);
    }
}
