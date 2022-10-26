// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import "forge-std/Test.sol";

import { ERC20 } from "@solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "@solmate/src/mixins/ERC4626.sol";

import { FixedMath } from "../../external/FixedMath.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
import { Divider, TokenHandler } from "../../Divider.sol";

import { AddressBook } from "../test-helpers/AddressBook.sol";
import { MockOracle } from "../test-helpers/mocks/fuse/MockOracle.sol";
import { Constants } from "../test-helpers/Constants.sol";

// Mainnet tests with imUSD 4626 token
contract ERC4626Adapters is Test {
    using FixedMath for uint256;

    uint256 public mainnetFork;

    ERC4626 public target;
    ERC20 public underlying;

    Divider public divider;
    TokenHandler internal tokenHandler;
    ERC4626Adapter public erc4626Adapter;
    MasterPriceOracle public masterOracle;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint8 public constant MODE = 0;
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant INITIAL_BALANCE = 1.25e18;

    function setUp() public {
        deal(AddressBook.IMUSD, address(this), 10e18);
        deal(AddressBook.MUSD, address(this), 10e18);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        target = ERC4626(AddressBook.IMUSD);
        underlying = ERC20(target.asset());

        // Deploy Chainlink price oracle
        ChainlinkPriceOracle chainlinkOracle = new ChainlinkPriceOracle(0);

        // Deploy Sense master price oracle
        address[] memory underlyings = new address[](1);
        underlyings[0] = AddressBook.MUSD;

        address[] memory oracles = new address[](1);
        oracles[0] = AddressBook.RARI_MSTABLE_ORACLE;

        masterOracle = new MasterPriceOracle(address(chainlinkOracle), underlyings, oracles);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(masterOracle),
            stake: AddressBook.WETH,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        erc4626Adapter = new ERC4626Adapter(
            address(divider),
            AddressBook.IMUSD,
            Constants.REWARDS_RECIPIENT,
            ISSUANCE_FEE,
            adapterParams
        ); // imUSD ERC-4626 adapter
    }

    function testMainnetERC4626AdapterScale() public {
        ERC4626 target = ERC4626(AddressBook.IMUSD);
        uint256 decimals = target.decimals();
        uint256 scale = target.convertToAssets(10**decimals) * 10**(18 - decimals);
        assertEq(erc4626Adapter.scale(), scale);
    }

    function testMainnetGetUnderlyingPrice() public {
        // Since the MasterPriceOracle uses Rari's master oracle, the prices should match
        uint256 price = IPriceFeed(AddressBook.RARI_ORACLE).price(AddressBook.MUSD);
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
        masterOracle.add(underlyings, oracles);

        uint256 price = oracle.price(address(underlying));
        assertEq(erc4626Adapter.getUnderlyingPrice(), price);
    }

    function testMainnetUnwrapTarget() public {
        uint256 uBalanceBefore = ERC20(AddressBook.MUSD).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.IMUSD).balanceOf(address(this));

        ERC20(AddressBook.IMUSD).approve(address(erc4626Adapter), tBalanceBefore);
        uint256 uDecimals = ERC20(AddressBook.MUSD).decimals();
        uint256 rate = ERC4626(AddressBook.IMUSD).convertToAssets(10**uDecimals);

        uint256 unwrapped = tBalanceBefore.fmul(rate, 10**uDecimals);
        erc4626Adapter.unwrapTarget(tBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.IMUSD).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.MUSD).balanceOf(address(this));

        assertEq(tBalanceAfter, 0);
        assertEq(uBalanceBefore + unwrapped, uBalanceAfter);
    }

    function testMainnetWrapUnderlying() public {
        // Trigger a deposit so if there's a pending yield it will collect and the exchange rate
        // gets updated
        ERC20(AddressBook.MUSD).approve(AddressBook.IMUSD, 1);
        ERC4626(AddressBook.IMUSD).deposit(1, address(this));

        uint256 uBalanceBefore = ERC20(AddressBook.MUSD).balanceOf(address(this));
        uint256 tBalanceBefore = ERC20(AddressBook.IMUSD).balanceOf(address(this));

        ERC20(AddressBook.MUSD).approve(address(erc4626Adapter), uBalanceBefore);
        uint256 uDecimals = ERC20(AddressBook.MUSD).decimals();
        uint256 rate = ERC4626(AddressBook.IMUSD).convertToAssets(10**uDecimals);

        uint256 wrapped = uBalanceBefore.fdivUp(rate, 10**uDecimals);
        erc4626Adapter.wrapUnderlying(uBalanceBefore);

        uint256 tBalanceAfter = ERC20(AddressBook.IMUSD).balanceOf(address(this));
        uint256 uBalanceAfter = ERC20(AddressBook.MUSD).balanceOf(address(this));

        assertEq(uBalanceAfter, 0);
        assertEq(tBalanceBefore + wrapped, tBalanceAfter);
    }
}
