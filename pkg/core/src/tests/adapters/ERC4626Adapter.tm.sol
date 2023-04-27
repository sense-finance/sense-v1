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
import { MockToken } from "../test-helpers/mocks/MockToken.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

interface Token {
    // IMUSD
    function depositInterest(uint256 _amount) external;

    // sanFRAX
    function stableMaster() external returns (address);

    // sanFRAX_Wrapper
    function sanToken() external returns (address);

    // sanFrax_Gauge
    function deposit(uint256 _amount) external;

    // stableMaster
    function deposit(
        uint256 amount,
        address user,
        address poolManager
    ) external;

    function mint(
        uint256 amount,
        address user,
        address poolManager,
        uint256 minStableAmount
    ) external;
}

interface IDLE {
    function idleToken() external returns (address);

    function mintIdleToken(
        uint256 _amount,
        bool,
        address _referral
    ) external returns (uint256 mintedTokens);

    function getAllAvailableTokens() external returns (address[] memory);
}

interface IAuraAdapterTestHelper {
    function increaseScale(uint64 swapSize) external;
}

interface ISturdyLendingPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
}

/// Mainnet tests
/// @dev reads from ENV the target address or defaults to imUSD 4626 token if none
/// @dev reads from ENV an address of a user with underlying balance. This is used in case tha
/// the `deal()` fails at finding the storage slot for the vault.
contract ERC4626Adapters is ForkTest {
    using FixedMath for uint256;

    ERC20 public underlying;
    ERC4626 public target;
    ERC4626Adapter public erc4626Adapter;
    address public userWithAssets; // address of a user with underlying balance
    uint256 public delta = 1;
    uint256 public deltaPercentage = 1; // e.g 0.001e18 = 0.1%
    uint256 public minAmount;

    function setUp() public virtual {
        // default env alues
        _setUp(true);
    }

    function _setUp(bool _fork) internal virtual {
        if (_fork) fork();

        try vm.envAddress("ERC4626_ADDRESS") returns (address _target) {
            target = ERC4626(_target);
        } catch {
            target = ERC4626(AddressBook.IMUSD);
        }
        console.log("Running tests for token: ", target.symbol());
        underlying = ERC20(target.asset());

        // set `userWithAssets` if exists
        try vm.envAddress("USER_WITH_ASSETS") returns (address _userWithAssets) {
            userWithAssets = _userWithAssets;
        } catch {}
        console.log("User with assets is: ", userWithAssets);

        // set `delta` if exists
        try vm.envUint("DELTA") returns (uint256 _delta) {
            delta = _delta;
        } catch {}
        console.log("Delta is: ", delta);

        // set `deltaPercentage` if exists
        try vm.envUint("DELTA_PERCENTAGE") returns (uint256 _deltaPercentage) {
            deltaPercentage = _deltaPercentage;
        } catch {}
        console.log("Delta percentage is: ", deltaPercentage);

        // set `minAmount` if exists
        try vm.envUint("MIN_AMOUNT") returns (uint256 _minAmount) {
            minAmount = _minAmount;
        } catch {}
        console.log("Min amount is: ", minAmount);

        if (address(underlying) == AddressBook.MUSD) {
            // Add Rari mStable oracle to Sense Oracle
            address[] memory underlyings = new address[](1);
            underlyings[0] = address(underlying);

            address[] memory oracles = new address[](1);
            oracles[0] = AddressBook.RARI_MSTABLE_ORACLE;
            vm.prank(AddressBook.SENSE_MULTISIG);
            MasterPriceOracle(AddressBook.SENSE_MASTER_ORACLE).add(underlyings, oracles);
        }

        if (address(underlying) == AddressBook.ws2USDC) {
            // Deposit some underlying if totalSupply is 0
            if (target.totalSupply() == 0) {
                address user = address(0xfede);
                deal(address(underlying), user, 1 * 10**underlying.decimals());
                vm.startPrank(user);
                underlying.approve(address(target), 1 * 10**underlying.decimals());
                target.deposit(1 * 10**underlying.decimals(), user);
                vm.stopPrank();
            }
        }

        // Add some balance of underlying to this contract
        deal(address(underlying), address(this), 10 * 10**underlying.decimals());

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
        Periphery(payable(AddressBook.PERIPHERY_1_4_0)).onboardAdapter(address(erc4626Adapter), true);
    }

    function testMainnetCantWrapMoreThanBalance() public virtual {
        uint256 balance = underlying.balanceOf(address(this));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        if (address(underlying) == AddressBook.STETH) {
            // Lido's 1 wei corner case: https://docs.lido.fi/guides/steth-integration-guide#1-wei-corner-case
            erc4626Adapter.wrapUnderlying(balance + 2);
        } else {
            erc4626Adapter.wrapUnderlying(balance + 1);
        }
    }

    function testMainnetCantUnwrapMoreThanBalance() public virtual {
        uint256 wrappedTarget = erc4626Adapter.wrapUnderlying(underlying.balanceOf(address(this)));
        assertEq(wrappedTarget, target.balanceOf(address(this)));

        vm.expectRevert();
        erc4626Adapter.unwrapTarget(wrappedTarget + 1);
    }

    // Not all ERC4626 implementations enforce this and it's not enforced by the standard
    // function testMainnetWrapUnwrapZeroAmt() public virtual {
    //     vm.expectRevert();
    //     erc4626Adapter.wrapUnderlying(0);

    //     vm.expectRevert();
    //     erc4626Adapter.unwrapTarget(0);
    // }

    function testMainnetWrapUnwrap(uint256 wrapAmt) public virtual {
        vm.assume(wrapAmt >= minAmount);

        // Trigger a small deposit so if there's a pending yield it will collect and the exchange rate gets updated
        underlying.approve(address(target), 1e6);
        target.deposit(1e6, address(this));

        // Run a full wrap -> unwrap cycle

        // 1. Wrap
        uint256 prebal = underlying.balanceOf(address(this));
        wrapAmt = bound(wrapAmt, 1, prebal);
        uint256 targetPrebal = target.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(wrapAmt);
        assertGt(targetFromWrap, 0);

        assertApproxEqAbs(underlying.balanceOf(address(this)), prebal - wrapAmt, delta);
        assertApproxEqAbs(target.balanceOf(address(this)), targetPrebal + targetFromWrap, delta);

        // some protocols will revert if doing two actions on the same block (e.g deposit followed by withdraw)
        vm.roll(block.number + 1);

        // 2. unwrap
        erc4626Adapter.unwrapTarget(targetFromWrap);
        uint256 postbal = underlying.balanceOf(address(this));

        assertApproxEqAbs(prebal, postbal, prebal.fmul(deltaPercentage));
    }

    function testMainnetScale() public virtual {
        uint256 tDecimals = target.decimals();
        uint256 uDecimals = ERC20(target.asset()).decimals();
        // convert to assets and scale to 18 decimals
        uint256 scale = target.convertToAssets(10**tDecimals) * 10**(18 - uDecimals);
        assertEq(erc4626Adapter.scale(), scale);
    }

    /// @notice scale() and scaleStored() have the same implementation
    /// @dev given the fact that totalAssets() might be implemented differently by each protocol,
    /// you may need to implement a custom case for the token given on _increaseVaultYield() function
    function testScaleAndScaleStored() public virtual {
        // Sanity check: vault is already initialised and scale > 0
        uint256 scale = erc4626Adapter.scale();
        uint256 scaleStored = erc4626Adapter.scaleStored();
        assertGt(scale, 0);
        assertGt(scaleStored, 0);

        // 1. Vault mutates by +2e18 tokens (simulated yield returned from strategy)
        _increaseVaultYield(2 * 10**underlying.decimals());

        // 2. Check that the value per share is now higher
        assertGt(
            erc4626Adapter.scale(),
            scale,
            "you may need to implement a custom case for this token on _increaseVaultYield() function"
        );
        assertGt(
            erc4626Adapter.scaleStored(),
            scaleStored,
            "you may need to implement a custom case for this token on _increaseVaultYield() function"
        );
    }

    function testScaleIsExRate() public virtual {
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
        uint256 scaleFactor = 10**(target.decimals() - underlying.decimals());
        uint256 uBal = (targetPrebal / 2).fmul(erc4626Adapter.scale()) / scaleFactor;
        assertApproxEqAbs(uBal, underlyingFromUnwrap, uBal.fmul(deltaPercentage));

        vm.roll(block.number + 1);

        // 3. Check that a wrapped amount reflects scale as an ex rate
        uint256 underlyingBalPre = underlying.balanceOf(address(this));
        uint256 targetFromWrap = erc4626Adapter.wrapUnderlying(underlyingBalPre / 2);
        uint256 tBal = (underlyingBalPre / 2).fdiv(erc4626Adapter.scale());
        assertApproxEqAbs(tBal, targetFromWrap / scaleFactor, tBal.fmul(deltaPercentage));
    }

    function testMainnetGetUnderlyingPrice() public virtual {
        // MasterPriceOracle uses Chainlink's data feeds as main source
        // We are comparing here with the prices from Rari's oracle and it should be approx the same (within 1%)
        uint256 price = IPriceFeed(AddressBook.RARI_ORACLE).price(address(underlying));
        assertApproxEqAbs(erc4626Adapter.getUnderlyingPrice(), price, price.fmul(0.01e18));
    }

    function testMainnetGetUnderlyingPriceWhenCustomOracle() public virtual {
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

    // utils

    function _increaseVaultYield(uint256 amt) internal virtual {
        // set balance if needed
        if (underlying.balanceOf(address(this)) < amt) deal(address(underlying), address(this), amt);

        if (address(target) == AddressBook.IMUSD) {
            deal(address(underlying), AddressBook.IMUSD_SAVINGS_MANAGER, amt);
            vm.prank(AddressBook.IMUSD_SAVINGS_MANAGER); // imUSD savings manager
            Token(address(target)).depositInterest(amt);
            return;
        }

        if (address(target) == AddressBook.BB_wstETH4626) {
            underlying.transfer(AddressBook.lido_stETH_CDO, amt);
            return;
        }

        if (address(target) == AddressBook.idleUSDCJunior4626) {
            IDLE idleToken = IDLE(IDLE(address(target)).idleToken());
            address[] memory tokens = idleToken.getAllAvailableTokens();
            deal(tokens[0], address(this), 1e18);
            ERC20(tokens[0]).transfer(address(idleToken), 1e18);
            return;
        }

        if (address(target) == AddressBook.sanFRAX_EUR_Wrapper) {
            deal(AddressBook.FRAX, address(this), amt);
            address sanToken = Token(address(target)).sanToken();
            address stableMaster = Token(sanToken).stableMaster();
            MockToken(AddressBook.FRAX).approve(stableMaster, amt);
            Token(stableMaster).mint(amt, address(this), AddressBook.FRAX_POOL_MANAGER, 0);

            vm.warp(block.timestamp + 1 days);
            return;
        }

        if (address(target) == AddressBook.ws2USDC) {
            address user = address(1);
            vm.startPrank(user);
            deal(address(underlying), user, 1e6);
            underlying.approve(AddressBook.LENDING_POOL, 1e6);
            ISturdyLendingPool(AddressBook.LENDING_POOL).deposit(AddressBook.USDC, 1e6, user, 0);
            uint256 bal = ERC20(AddressBook.sUSDC).balanceOf(user);
            ERC20(AddressBook.sUSDC).transfer(address(target), bal);
            vm.stopPrank();
            return;
        }

        // try mutating vault by transfering underlying to the vault
        underlying.transfer(address(target), amt);
    }

    function deal(
        address token,
        address to,
        uint256 amt
    ) internal override {
        if (userWithAssets == address(0)) {
            super.deal(token, to, amt);
        } else {
            vm.prank(userWithAssets);
            underlying.transfer(to, amt);
        }
    }
}
