// SPDX-License-Identifier: AGPL-3.0-only

// TODO: this tests fail because they were using the 4626 factory that was deprecated
// once we set the new one, uncomment!
pragma solidity 0.8.15;

// import { ERC20 } from "solmate/tokens/ERC20.sol";
// import { ERC4626 } from "solmate/mixins/ERC4626.sol";
// import { FixedMath } from "../../external/FixedMath.sol";
// import { ERC4626Adapter } from "../../adapters/abstract/erc4626/ERC4626Adapter.sol";
// import { BaseFactory } from "../../adapters/abstract/factories/BaseFactory.sol";
// import { ERC4626Factory } from "../../adapters/abstract/factories/ERC4626Factory.sol";

// import { EulerERC4626WrapperFactory } from "../../adapters/abstract/erc4626/yield-daddy/euler/EulerERC4626WrapperFactory.sol";
// import { EulerERC4626 } from "../../adapters/abstract/erc4626/yield-daddy/euler/EulerERC4626.sol";
// import { IEulerMarkets } from "@yield-daddy/src/euler/external/IEulerMarkets.sol";

// import { IPriceFeed } from "../../adapters/abstract/IPriceFeed.sol";
// import { MasterPriceOracle } from "../../adapters/implementations/oracles/MasterPriceOracle.sol";
// import { ChainlinkPriceOracle } from "../../adapters/implementations/oracles/ChainlinkPriceOracle.sol";
// import { Divider } from "../../Divider.sol";
// import { Periphery } from "../../Periphery.sol";

// import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
// import { MockOracle } from "../test-helpers/mocks/fuse/MockOracle.sol";
// import { Constants } from "../test-helpers/Constants.sol";
// import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

// interface EulerERC4626Like {
//     function eToken() external returns (address);

//     function euler() external returns (address);
// }

// interface IEulerTokenLike {
//     function deposit(uint256 subAccountId, uint256 amount) external;

//     function balanceOfUnderlying(address) external returns (uint256);
// }

// // Mainnet tests with imUSD 4626 token
// contract ERC4626EulerAdapters is ForkTest {
//     using FixedMath for uint256;

//     ERC4626 public target;
//     ERC20 public underlying;

//     uint256 public decimals;

//     Divider public divider = Divider(AddressBook.DIVIDER_1_2_0);
//     Periphery public periphery = Periphery(payable(AddressBook.PERIPHERY_1_4_0));
//     ERC4626Factory public factory = ERC4626Factory(AddressBook.ERC4626_FACTORY);
//     ERC4626Adapter public adapter;

//     // Timeless
//     EulerERC4626WrapperFactory public wFactory;

//     uint16 public constant MODE = 0;
//     uint64 public constant ISSUANCE_FEE = 0.01e18;
//     uint256 public constant STAKE_SIZE = 1e18;
//     uint256 public constant MIN_MATURITY = 2 weeks;
//     uint256 public constant MAX_MATURITY = 14 weeks;
//     uint256 public constant DEFAULT_GUARD = 100000 * 1e18;

//     uint256 public constant INITIAL_BALANCE = 10**6;

//     function setUp() public {
//         fork();

//         // Deploy a Euler 4626 Wrapper Factory
//         wFactory = new EulerERC4626WrapperFactory(
//             AddressBook.EULER,
//             IEulerMarkets(AddressBook.EULER_MARKETS),
//             Constants.RESTRICTED_ADMIN,
//             Constants.REWARDS_RECIPIENT
//         );

//         // Deploy a 4626 Wrapper for Euler USDC market
//         target = wFactory.createERC4626(ERC20(AddressBook.USDC));
//         decimals = target.decimals();

//         // Can call .asset() and is USDC
//         underlying = ERC20(target.asset());
//         assertEq(address(underlying), AddressBook.USDC);

//         // Fund wallet with USDC
//         deal(address(underlying), address(this), 5 * 10**decimals);

//         // Support deployed target
//         vm.prank(AddressBook.SENSE_MULTISIG);
//         factory.supportTarget(address(target), true);

//         // Deploy Euler USDC ERC4626 Wrapper Adapter
//         adapter = ERC4626Adapter(periphery.deployAdapter(address(factory), address(target), ""));
//     }

//     function testMainnetERC4626AdapterScale() public {
//         uint256 scale = target.convertToAssets(10**decimals) * 10**(18 - decimals);
//         assertEq(adapter.scale(), scale);
//     }

//     function testMainnetGetUnderlyingPrice() public {
//         // Since the MasterPriceOracle uses Rari's master oracle, the prices should match
//         uint256 price = IPriceFeed(AddressBook.RARI_ORACLE).price(AddressBook.USDC);
//         assertEq(adapter.getUnderlyingPrice(), price);
//     }

//     function testMainnetUnwrapTarget() public {
//         // get weUSDC (Wrapped Euler USDC) by wrapping USDC
//         uint256 uBal = underlying.balanceOf(address(this));
//         underlying.approve(address(adapter), uBal);
//         adapter.wrapUnderlying(uBal);

//         uint256 uBalanceBefore = underlying.balanceOf(address(this));
//         uint256 tBalanceBefore = target.balanceOf(address(this));

//         target.approve(address(adapter), tBalanceBefore);
//         uint256 rate = target.convertToAssets(10**decimals);
//         uint256 unwrapped = tBalanceBefore.fmul(rate, 10**decimals);
//         adapter.unwrapTarget(tBalanceBefore);

//         uint256 tBalanceAfter = target.balanceOf(address(this));
//         uint256 uBalanceAfter = underlying.balanceOf(address(this));

//         assertEq(tBalanceAfter, 0);
//         // NOTE: assertApproxEqAbs because when we deposit on Euler we lose precision by 1
//         assertApproxEqAbs(uBalanceBefore + unwrapped, uBalanceAfter);
//     }

//     function testMainnetWrapUnderlying() public {
//         // Deposit 1 USDC to initialise the vault
//         uint256 uBal = 10**decimals;
//         underlying.approve(address(target), uBal);
//         target.deposit(uBal, address(this));

//         uint256 uBalanceBefore = underlying.balanceOf(address(this));
//         uint256 tBalanceBefore = target.balanceOf(address(this));

//         underlying.approve(address(adapter), uBalanceBefore);

//         uint256 rate = target.convertToAssets(10**decimals);
//         uint256 wrapped = uBalanceBefore.fdivUp(rate, 10**decimals);
//         adapter.wrapUnderlying(uBalanceBefore);

//         uint256 tBalanceAfter = target.balanceOf(address(this));
//         uint256 uBalanceAfter = underlying.balanceOf(address(this));

//         assertEq(uBalanceAfter, 0);
//         // NOTE: assertApproxEqAbs because when we deposit on Euler we lose precision by 1
//         assertApproxEqAbs(tBalanceBefore + wrapped, tBalanceAfter);
//     }

//     function testMainnetWrapUnwrap(uint256 wrapAmt) public {
//         wrapAmt = bound(wrapAmt, 10, INITIAL_BALANCE);

//         // Approvals
//         target.approve(address(adapter), type(uint256).max);
//         underlying.approve(address(adapter), type(uint256).max);

//         // 1. Run a full wrap -> unwrap cycle
//         uint256 prebal = underlying.balanceOf(address(this));
//         uint256 targetFromWrap = adapter.wrapUnderlying(wrapAmt);
//         assertEq(targetFromWrap, target.balanceOf(address(this)));
//         assertGt(targetFromWrap, 0);
//         adapter.unwrapTarget(targetFromWrap);
//         uint256 postbal = underlying.balanceOf(address(this));

//         assertApproxEqAbs(prebal, postbal);

//         // 2. Deposit underlying tokens into the vault
//         underlying.approve(address(target), INITIAL_BALANCE / 2);
//         target.deposit(INITIAL_BALANCE / 4, address(this));
//         assertEq(target.totalSupply(), INITIAL_BALANCE / 4);
//         assertEq(target.totalAssets(), INITIAL_BALANCE / 4);
//         // 3. Init a greater-than-one exchange rate
//         target.deposit(INITIAL_BALANCE / 4, address(this));
//         assertEq(target.totalSupply(), INITIAL_BALANCE / 2);
//         assertEq(target.totalAssets(), INITIAL_BALANCE / 2);
//         uint256 targetBalPostDeposit = target.balanceOf(address(this));

//         // Bound wrap amount to remaining tokens (tokens not deposited)
//         wrapAmt = bound(wrapAmt, 1, INITIAL_BALANCE / 2);

//         // 4. Run the cycle again now that the vault has some underlying tokens of its own
//         prebal = underlying.balanceOf(address(this));
//         targetFromWrap = adapter.wrapUnderlying(wrapAmt);
//         assertEq(targetFromWrap + targetBalPostDeposit, target.balanceOf(address(this)));
//         assertGt(targetFromWrap + targetBalPostDeposit, 0);
//         adapter.unwrapTarget(targetFromWrap);
//         postbal = underlying.balanceOf(address(this));

//         assertEq(prebal, postbal);
//     }

//     function testMainnetScale() public {
//         // 1. Deposit initial underlying tokens into the vault
//         underlying.approve(address(target), INITIAL_BALANCE);
//         target.deposit(INITIAL_BALANCE, address(this));

//         // Initializes at 1:1
//         // NOTE: When we do deposits on Euler, we lose precision
//         // so I'm denormalising the scale to 1e18 to then do assertApproxEqAbs
//         uint256 denormalisedScale = adapter.scale() / 10**(18 - decimals);
//         assertApproxEqAbs(denormalisedScale, 10**decimals);

//         // 2. Vault mutates by +2e6 tokens (simulated yield returned from strategy)
//         address eToken = EulerERC4626Like(address(target)).eToken();

//         // Deposit 2 USDC into Euler USDC token
//         vm.startPrank(address(target));
//         uint256 uBal = 2 * 10**decimals;
//         deal(address(underlying), address(target), uBal); // mint 5 USDC to taget (wrapper)

//         address euler = EulerERC4626Like(address(target)).euler();
//         underlying.approve(euler, uBal); // approve Euler (not the eUSDC) to be able to pull USDCC
//         IEulerTokenLike(eToken).deposit(0, uBal);
//         vm.stopPrank();

//         // 3. Check that the value per share is now higher
//         assertGt(adapter.scale(), 1e18);

//         denormalisedScale = adapter.scale() / 10**(18 - decimals);
//         assertApproxEqAbs(denormalisedScale, ((INITIAL_BALANCE + 2 * 10**decimals) * 10**decimals) / INITIAL_BALANCE);
//     }

//     /// @notice scale() and scaleStored() have the same implementation
//     function testMainnetScaleAndScaleStored() public {
//         // 1. Deposit initial underlying tokens into the vault
//         underlying.approve(address(target), INITIAL_BALANCE);
//         target.deposit(INITIAL_BALANCE, address(this));

//         // Initializes at 1:1
//         // NOTE: When we do deposits on Euler, we lose precision
//         // so I'm denormalising the scale to 1e18 to then do assertApproxEqAbs
//         uint256 denormalisedScale = adapter.scale() / 10**(18 - decimals);
//         uint256 denormalisedScaleStored = adapter.scaleStored() / 10**(18 - decimals);
//         assertApproxEqAbs(denormalisedScale, 10**decimals);
//         assertApproxEqAbs(denormalisedScaleStored, 10**decimals);

//         // 2. Vault mutates by +2e6 tokens (simulated yield returned from strategy)
//         address eToken = EulerERC4626Like(address(target)).eToken();

//         // Deposit 2 USDC into Euler USDC token
//         vm.startPrank(address(target));
//         uint256 uBal = 2 * 10**decimals;
//         deal(address(underlying), address(target), uBal); // mint 5 USDC to taget (wrapper)

//         address euler = EulerERC4626Like(address(target)).euler();
//         underlying.approve(euler, uBal); // approve Euler (not the eUSDC) to be able to pull USDCC
//         IEulerTokenLike(eToken).deposit(0, uBal);
//         vm.stopPrank();

//         // 3. Check that the value per share is now higher
//         assertGt(adapter.scale(), 1e18);
//         assertGt(adapter.scaleStored(), 1e18);

//         denormalisedScale = adapter.scale() / 10**(18 - decimals);
//         denormalisedScaleStored = adapter.scaleStored() / 10**(18 - decimals);
//         uint256 expectedDenormalisedScale = ((INITIAL_BALANCE + 2 * 10**decimals) * 10**decimals) / INITIAL_BALANCE;
//         assertApproxEqAbs(denormalisedScale, expectedDenormalisedScale);
//         assertApproxEqAbs(denormalisedScaleStored, expectedDenormalisedScale);
//     }

//     function testMainnetScaleIsExRate() public {
//         // 1. Deposit initial underlying tokens into the vault and simulate yield returns
//         underlying.approve(address(target), INITIAL_BALANCE / 2);
//         target.deposit(INITIAL_BALANCE / 2, address(this));
//         // underlying.transfer(address(target), 2*10**decimals);

//         // 2. Vault mutates by +2e6 tokens (simulated yield returned from strategy)
//         address eToken = EulerERC4626Like(address(target)).eToken();

//         // Deposit 2 USDC into Euler USDC token
//         vm.startPrank(address(target));
//         uint256 uBal = 2 * 10**decimals;
//         deal(address(underlying), address(target), uBal); // mint 5 USDC to taget (wrapper)

//         address euler = EulerERC4626Like(address(target)).euler();
//         underlying.approve(euler, uBal); // approve Euler (not the eUSDC) to be able to pull USDCC
//         IEulerTokenLike(eToken).deposit(0, uBal);
//         vm.stopPrank();

//         // 3. Check that an unwrapped amount reflects scale as an ex rate
//         uint256 targetBalPre = target.balanceOf(address(this));
//         // Sanity check
//         assertGt(targetBalPre, 0);
//         // Approvals
//         target.approve(address(adapter), type(uint256).max);
//         underlying.approve(address(adapter), type(uint256).max);
//         // Leave something in the vault
//         uint256 underlyingFromUnwrap = adapter.unwrapTarget(targetBalPre / 2);
//         assertApproxEqAbs(((targetBalPre / 2) * adapter.scale()) / 1e18, underlyingFromUnwrap);

//         // 4. Check that a wrapped amount reflects scale as an ex rate
//         uint256 underlyingBalPre = underlying.balanceOf(address(this));
//         uint256 targetFromWrap = adapter.wrapUnderlying(underlyingBalPre / 2);
//         assertApproxEqAbs(((underlyingBalPre / 2) * 1e18) / adapter.scale(), targetFromWrap);
//     }

//     // helpers

//     function assertApproxEqAbs(uint256 a, uint256 b) public {
//         assertApproxEqAbs(a, b, 100);
//     }
// }
