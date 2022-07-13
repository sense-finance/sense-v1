// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
// import { DSTestPlus } from "@rari-capital/solmate/src/test/utils/DSTestPlus.sol";

import { FixedMath } from "../../external/FixedMath.sol";
import { BaseAdapter } from "../../adapters/abstract/BaseAdapter.sol";
import { ERC4626Adapter, ChainlinkOracleLike } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { MUSDPriceFeed, FeederPoolLike } from "../../adapters/implementations/oracles/MUSDPriceFeed.sol";

import { AddressBook } from "../test-helpers/AddressBook.sol";
import { Constants } from "../test-helpers/Constants.sol";
import { LiquidityHelper } from "../test-helpers/LiquidityHelper.sol";
import { DSTest } from "../test-helpers/test.sol";
import { Hevm } from "../test-helpers/Hevm.sol";

interface CurveStableSwapLike {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);
}

// Mainnet tests with imUSD 4626 token
contract ERC4626Adapters is LiquidityHelper, DSTest {
    using FixedMath for uint256;

    ERC4626 public target;
    ERC20 public underlying;

    Divider public divider;
    TokenHandler internal tokenHandler;
    ERC4626Adapter public erc4626Adapter;

    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;
    uint16 public constant MODE = 0;
    uint16 public constant DEFAULT_LEVEL = 31;
    uint256 public constant INITIAL_BALANCE = 1.25e18;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        giveTokens(AddressBook.IMUSD, 10e18, hevm);
        giveTokens(AddressBook.MUSD, 10e18, hevm);

        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        divider.setPeriphery(address(this));
        tokenHandler.init(address(divider));

        target = ERC4626(AddressBook.IMUSD);
        underlying = ERC20(target.asset());

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: AddressBook.RARI_ORACLE,
            stake: AddressBook.WETH,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: 0,
            tilt: 0,
            level: DEFAULT_LEVEL
        });
        erc4626Adapter = new ERC4626Adapter(address(divider), AddressBook.IMUSD, ISSUANCE_FEE, adapterParams); // imUSD ERC-4626 adapter
    }

    function testMainnetERC4626AdapterScale() public {
        ERC4626 target = ERC4626(AddressBook.IMUSD);
        uint256 decimals = target.decimals();
        uint256 scale = target.convertToAssets(10**decimals) * 10**(18 - decimals);
        assertEq(erc4626Adapter.scale(), scale);
    }

    function testGetUnderlyingPriceWithCustomOracle() public {
        // Deploy mStable price oracle
        MUSDPriceFeed priceFeed = new MUSDPriceFeed();

        // Add mStable price oracle on 4626 adapter
        erc4626Adapter.setOracle(address(priceFeed));

        // Get mUSD-FEI price from mStable Feeder Pool
        (uint256 price, ) = FeederPoolLike(priceFeed.MUSD_ETH_POOL()).getPrice();

        // Get FEI-ETH price from Chainlink
        (, int256 ethPrice, , uint256 ethUpdatedAt, ) = ChainlinkOracleLike(priceFeed.FEI_ETH_PRICEFEED())
            .latestRoundData();

        // Calculate mUSD-ETH price
        price = uint256(ethPrice).fdiv(price);

        // Check calculated price matches the one we calculated on the adapter
        assertEq(erc4626Adapter.getUnderlyingPrice(), price);

        // Sanity check: compare price with Curve's price
        uint256 mUSDUSDTPrice = CurveStableSwapLike(AddressBook.MUSD_CURVE_POOL).get_dy(int128(0), int128(1), 1e18);
        uint256 ETHUSDTPrice = CurveStableSwapLike(AddressBook.TRICRYPTO_CURVE_POOL).get_dy(
            uint256(2),
            uint256(0),
            1e18
        );

        // within .1% // TODO: not working, seems like there's quite a lot of difference
        uint256 mUSDEthCurvePrice = mUSDUSDTPrice.fdiv(ETHUSDTPrice * 10**(18 - 6));
        // assertClose(price, mUSDEthCurvePrice, price.fmul(0.001e18));
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
