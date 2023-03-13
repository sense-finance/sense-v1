// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// // Internal references
// import { FixedMath } from "@sense-finance/v1-core/external/FixedMath.sol";
// import { Divider, TokenHandler } from "@sense-finance/v1-core/Divider.sol";
// import { CAdapter } from "@sense-finance/v1-core/adapters/implementations/compound/CAdapter.sol";
// import { CToken } from "@sense-finance/v1-fuse/external/CToken.sol";
// import { Token } from "@sense-finance/v1-core/tokens/Token.sol";
// import { PoolManager, MasterOracleLike } from "../PoolManager.sol";
// import { BaseAdapter } from "@sense-finance/v1-core/adapters/abstract/BaseAdapter.sol";

// import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
// import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";
// import { MockFactory } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockFactory.sol";
// import { MockOracle } from "@sense-finance/v1-core/tests/test-helpers/mocks/fuse/MockOracle.sol";
// import { MockTarget } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockTarget.sol";
// import { MockToken } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockToken.sol";
// import { MockAdapter } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockAdapter.sol";
// import { DateTimeFull } from "@sense-finance/v1-core/tests/test-helpers/DateTimeFull.sol";
// import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
// import { Constants } from "@sense-finance/v1-core/tests/test-helpers/Constants.sol";
// import { MockBalancerVault, MockSpaceFactory, MockSpacePool } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockSpace.sol";
// import { PriceOracle } from "../external/PriceOracle.sol";

// interface ComptrollerLike {
//     function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);

//     function cTokensByUnderlying(address underlying) external view returns (address);

//     function borrowAllowed(
//         address cToken,
//         address borrower,
//         uint256 borrowAmount
//     ) external returns (uint256);

//     struct Market {
//         bool isListed;
//         uint256 collateralFactorMantissa;
//     }

//     function markets(address cToken) external view returns (Market memory);
// }

// contract PoolManagerTest is ForkTest {
//     using FixedMath for uint256;

//     MockToken internal stake;
//     MockTarget internal target;
//     Divider internal divider;
//     TokenHandler internal tokenHandler;
//     MockAdapter internal mockAdapter;
//     MockOracle internal mockOracle;

//     PoolManager internal poolManager;

//     MockBalancerVault internal balancerVault;
//     MockSpaceFactory internal spaceFactory;

//     function setUp() public {
//         fork();

//         tokenHandler = new TokenHandler();
//         divider = new Divider(address(this), address(tokenHandler));
//         tokenHandler.init(address(divider));
//         mockOracle = new MockOracle();

//         poolManager = new PoolManager(
//             AddressBook.POOL_DIR,
//             AddressBook.COMPTROLLER_IMPL,
//             AddressBook.CERC20_IMPL,
//             address(divider),
//             AddressBook.MASTER_ORACLE_IMPL
//         );

//         // Enable the adapter
//         divider.setPeriphery(address(this));

//         MockToken underlying = new MockToken("Underlying Token", "UD", 18);
//         stake = new MockToken("Stake", "SBL", 18);
//         target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

//         BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
//             oracle: address(mockOracle),
//             stake: address(stake),
//             stakeSize: 1e18,
//             minm: 2 weeks,
//             maxm: 14 weeks,
//             mode: 0,
//             tilt: 0,
//             level: 31
//         });
//         mockAdapter = new MockAdapter(
//             address(divider),
//             address(target),
//             target.underlying(),
//             Constants.REWARDS_RECIPIENT,
//             0.1e18,
//             adapterParams
//         );

//         // Ping scale to set an lscale
//         mockAdapter.scale();
//         divider.setAdapter(address(mockAdapter), true);

//         balancerVault = new MockBalancerVault();
//         spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));
//         balancerVault.setSpaceFactory(address(spaceFactory));
//     }

//     function testMainnetDeployPool() public {
//         uint256 maturity = _getValidMaturity();
//         _initSeries(maturity);

//         assertTrue(poolManager.comptroller() == address(0));
//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);

//         assertTrue(poolManager.comptroller() != address(0));

//         // Can't deploy pool twice
//         vm.expectRevert("ERC1167: create2 failed");
//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);
//     }

//     function testMainnetAddTarget() public {
//         // Cannot add a Target before deploying a pool
//         vm.expectRevert(abi.encodeWithSelector(Errors.PoolNotDeployed.selector));
//         poolManager.addTarget(address(target), address(mockAdapter));

//         // Can add a Target after deploying a pool
//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);

//         // Cannot add a Target before params have been set
//         vm.expectRevert(abi.encodeWithSelector(Errors.TargetParamsNotSet.selector));
//         poolManager.addTarget(address(target), address(mockAdapter));

//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);

//         // Can now add Target
//         poolManager.addTarget(address(target), address(mockAdapter));

//         vm.expectRevert();
//         poolManager.addTarget(address(target), address(mockAdapter));
//     }

//     function testMainnetQueueSeries() public {
//         uint256 maturity = _getValidMaturity();

//         // Cannot queue non-existant Series
//         vm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
//         poolManager.queueSeries(address(mockAdapter), maturity, address(0));

//         _initSeries(maturity);

//         // Cannot queue if the Fuse pool has not been deployed (no comptroller)
//         vm.expectRevert();
//         poolManager.queueSeries(address(mockAdapter), maturity, address(0));

//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);

//         // Cannot queue if Target has not been added to the Fuse pool
//         vm.expectRevert(abi.encodeWithSelector(Errors.TargetNotInFuse.selector));
//         poolManager.queueSeries(address(mockAdapter), maturity, address(0));

//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);
//         poolManager.addTarget(address(target), address(mockAdapter));

//         poolManager.queueSeries(address(mockAdapter), maturity, address(0));
//     }

//     function testMainnetAddSeries() public {
//         uint256 maturity = _getValidMaturity();
//         _initSeries(maturity);

//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);
//         PoolManager.AssetParams memory paramsTarget = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", paramsTarget);
//         address cTarget = poolManager.addTarget(address(target), address(mockAdapter));

//         address pool = spaceFactory.create(address(mockAdapter), maturity);

//         // Cannot add Series if it hasn't been queued
//         vm.expectRevert(abi.encodeWithSelector(Errors.SeriesNotQueued.selector));
//         poolManager.addSeries(address(mockAdapter), maturity);

//         poolManager.queueSeries(address(mockAdapter), maturity, pool);

//         // Cannot add Series if params aren't set
//         vm.expectRevert(abi.encodeWithSelector(Errors.PTParamsNotSet.selector));
//         poolManager.addSeries(address(mockAdapter), maturity);

//         poolManager.setParams(
//             "PT_PARAMS",
//             PoolManager.AssetParams({
//                 irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//                 reserveFactor: 0.1 ether,
//                 collateralFactor: 0.5 ether
//             })
//         );

//         poolManager.setParams(
//             "LP_TOKEN_PARAMS",
//             PoolManager.AssetParams({
//                 irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//                 reserveFactor: 0.1 ether,
//                 collateralFactor: 0.5 ether
//             })
//         );

//         (address cPT, address cLPToken) = poolManager.addSeries(address(mockAdapter), maturity);
//         ComptrollerLike comptroller = ComptrollerLike(poolManager.comptroller());

//         assertTrue(cPT != address(0));
//         assertTrue(cLPToken != address(0));

//         address[] memory cTokens = new address[](3);
//         cTokens[0] = address(cTarget);
//         cTokens[1] = address(cPT);
//         cTokens[2] = address(cLPToken);

//         ComptrollerLike(comptroller).enterMarkets(cTokens);

//         uint256 TARGET_IN = 1.1e18;

//         // Mint some liquidity for lending/borrowing
//         Token(MockSpacePool(pool).target()).mint(address(balancerVault), 1e18);
//         MockSpacePool(pool).mint(address(this), 1e18);

//         target.mint(address(this), TARGET_IN);
//         target.approve(cTarget, TARGET_IN);
//         uint256 originalTargetBalance = target.balanceOf(address(this));
//         uint256 err = CToken(cTarget).mint(TARGET_IN);
//         assertEq(err, 0);

//         // Has the initial Target's value in cTarget
//         assertEq(
//             (Token(cTarget).balanceOf(address(this)) * CToken(cTarget).exchangeRateCurrent()) /
//                 10**CToken(cTarget).decimals(),
//             TARGET_IN
//         );

//         err = ComptrollerLike(comptroller).borrowAllowed(address(cPT), address(this), 1e18);
//         // Insufficient liquidity
//         assertEq(err, 4);

//         vm.expectRevert("borrow is paused");
//         ComptrollerLike(comptroller).borrowAllowed(address(cLPToken), address(this), 1e18);

//         err = CToken(cTarget).redeem(Token(cTarget).balanceOf(address(this)));
//         assertEq(err, 0);
//         assertEq(target.balanceOf(address(this)), originalTargetBalance);
//     }

//     function testMainnetAdminPassthrough() public {
//         poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, AddressBook.RARI_ORACLE);
//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);

//         // re-create add target

//         address underlying = mockAdapter.underlying();

//         address[] memory underlyings = new address[](2);
//         underlyings[0] = address(target);
//         underlyings[1] = underlying;

//         PriceOracle[] memory oracles = new PriceOracle[](2);
//         oracles[0] = PriceOracle(poolManager.targetOracle());
//         oracles[1] = PriceOracle(poolManager.masterOracle());

//         poolManager.execute(
//             poolManager.underlyingOracle(),
//             0,
//             abi.encodeWithSignature("setUnderlying(address,address)", underlying, address(mockAdapter)),
//             gasleft() - 100000
//         );
//         poolManager.execute(
//             poolManager.targetOracle(),
//             0,
//             abi.encodeWithSignature("setTarget(address,address)", address(target), address(mockAdapter)),
//             gasleft() - 100000
//         );

//         poolManager.execute(
//             poolManager.masterOracle(),
//             0,
//             abi.encodeWithSignature("add(address[],address[])", underlyings, oracles),
//             gasleft() - 100000
//         );

//         bytes memory constructorData = abi.encode(
//             target,
//             poolManager.comptroller(),
//             0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             target.name(),
//             target.symbol(),
//             poolManager.cERC20Impl(),
//             hex"", // calldata sent to becomeImplementation (empty bytes b/c it's currently unused)
//             0.1 ether,
//             0 // no admin fee
//         );

//         // Can now add Target with the passthrough
//         bool success = poolManager.execute(
//             poolManager.comptroller(),
//             0,
//             abi.encodeWithSignature("_deployMarket(bool,bytes,uint256)", false, constructorData, 0.5 ether),
//             gasleft() - 100000
//         );
//         assertTrue(success);

//         // shouldn't be able to add target again
//         vm.expectRevert();
//         poolManager.addTarget(address(target), address(mockAdapter));

//         address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(target));

//         vm.roll(1);

//         success = poolManager.execute(
//             poolManager.comptroller(),
//             0,
//             abi.encodeWithSignature("_unsupportMarket(address)", cTarget),
//             gasleft() - 100000
//         );
//         assertTrue(success);

//         // should be able to add target again after it's been un-supported
//         poolManager.addTarget(address(target), address(mockAdapter));
//     }

//     function _getValidMaturity() internal view returns (uint256 maturity) {
//         (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp + 10 weeks);
//         maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
//     }

//     function _initSeries(uint256 maturity) internal {
//         // Setup mock stake token
//         stake.mint(address(this), 1000 ether);
//         stake.approve(address(divider), 1000 ether);

//         divider.initSeries(address(mockAdapter), maturity, address(this));
//     }
// }
