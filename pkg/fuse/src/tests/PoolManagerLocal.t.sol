// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// // Internal references
// import { FixedMath } from "@sense-finance/v1-core/external/FixedMath.sol";
// import { Divider, TokenHandler } from "@sense-finance/v1-core/Divider.sol";
// import { CAdapter } from "@sense-finance/v1-core/adapters/implementations/compound/CAdapter.sol";
// import { Token } from "@sense-finance/v1-core/tokens/Token.sol";
// import { Token } from "@sense-finance/v1-core/tokens/Token.sol";
// import { PoolManager } from "../PoolManager.sol";
// import { TestHelper } from "@sense-finance/v1-core/tests/test-helpers/TestHelper.sol";
// import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

// import { MockFactory } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockFactory.sol";
// import { MockOracle } from "@sense-finance/v1-core/tests/test-helpers/mocks/fuse/MockOracle.sol";
// import { MockComptrollerRejectAdmin, MockComptrollerFailAddMarket } from "@sense-finance/v1-core/tests/test-helpers/mocks/fuse/MockComptroller.sol";
// import { MockFuseDirectory } from "@sense-finance/v1-core/tests/test-helpers/mocks/fuse/MockFuseDirectory.sol";
// import { MockTarget } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockTarget.sol";
// import { MockToken } from "@sense-finance/v1-core/tests/test-helpers/mocks/MockToken.sol";
// import { DateTimeFull } from "@sense-finance/v1-core/tests/test-helpers/DateTimeFull.sol";

// contract PoolManagerLocalTest is TestHelper {
//     using FixedMath for uint256;
//     using Errors for string;

//     function testDeployPoolManager() public {
//         PoolManager pm = new PoolManager(address(1), address(2), address(3), address(4), address(5));
//         assertEq(pm.fuseDirectory(), address(1));
//         assertEq(pm.comptrollerImpl(), address(2));
//         assertEq(pm.cERC20Impl(), address(3));
//         assertEq(pm.divider(), address(4));
//         assertEq(pm.oracleImpl(), address(5));
//         assertTrue(pm.targetOracle() != address(0));
//         assertTrue(pm.ptOracle() != address(0));
//         assertTrue(pm.lpOracle() != address(0));
//         assertTrue(pm.underlyingOracle() != address(0));
//     }

//     /* ========== deployPool() tests ========== */

//     function testCantDeployPoolIfFailToBecomeAdmin() public {
//         comptroller = new MockComptrollerRejectAdmin();
//         fuseDirectory = new MockFuseDirectory(address(comptroller));
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         vm.expectRevert(abi.encodeWithSelector(Errors.FailedBecomeAdmin.selector));
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(masterOracle));
//     }

//     function testCantDeployPoolIfExists() public {
//         vm.expectRevert("ERC1167: create2 failed");
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(masterOracle));
//     }

//     function testDeployPool() public {
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         assertTrue(poolManager.masterOracle() != address(0));
//         assertTrue(poolManager.comptroller() != address(0));
//     }

//     /* ========== addTarget() tests ========== */

//     function testCantAddTargetIfPooledNotDeployed() public {
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         vm.expectRevert(abi.encodeWithSelector(Errors.PoolNotDeployed.selector));
//         poolManager.addTarget(address(target), address(adapter));
//     }

//     function testCantAddTargetIfTargetParamsNotSet() public {
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         vm.expectRevert(abi.encodeWithSelector(Errors.TargetParamsNotSet.selector));
//         poolManager.addTarget(address(target), address(adapter));
//     }

//     function testCantAddTargetIfFailedToAddMarket() public {
//         comptroller = new MockComptrollerFailAddMarket();
//         fuseDirectory = new MockFuseDirectory(address(comptroller));
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);
//         vm.expectRevert(abi.encodeWithSelector(Errors.FailedAddTargetMarket.selector));
//         poolManager.addTarget(address(target), address(adapter));
//     }

//     function testAddTarget() public {
//         MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);
//         poolManager.addTarget(address(otherTarget), address(adapter));
//     }

//     /* ========== queueSeries() tests ========== */

//     function testCantQueueSeriesIfPoolNotDeployed() public {
//         uint256 maturity = getValidMaturity(2021, 10);
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );
//         vm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
//         poolManager.queueSeries(address(adapter), maturity, address(123));
//     }

//     function testCantQueueSeriesIfSeriesNotExists() public {
//         uint256 maturity = getValidMaturity(2021, 10);
//         vm.expectRevert(abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
//         poolManager.queueSeries(address(adapter), maturity, address(123));
//     }

//     function testCantQueueSeriesIfAlreadyQueued() public {
//         MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
//         uint256 maturity = getValidMaturity(2021, 10);
//         divider.setPeriphery(alice);
//         stake.approve(address(divider), type(uint256).max);
//         stake.mint(alice, 1000e18);
//         divider.initSeries(address(adapter), maturity, alice);

//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );

//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);
//         poolManager.addTarget(address(otherTarget), address(adapter));

//         poolManager.queueSeries(address(adapter), maturity, address(123));
//         vm.expectRevert(abi.encodeWithSelector(Errors.DuplicateSeries.selector));
//         poolManager.queueSeries(address(adapter), maturity, address(123));
//     }

//     function testQueueSeries() public {
//         MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
//         uint256 maturity = getValidMaturity(2021, 10);
//         divider.setPeriphery(alice);
//         stake.approve(address(divider), type(uint256).max);
//         stake.mint(alice, 1000e18);
//         divider.initSeries(address(adapter), maturity, alice);
//         PoolManager poolManager = new PoolManager(
//             address(fuseDirectory),
//             address(comptroller),
//             address(1),
//             address(divider),
//             address(masterOracle) // oracle impl
//         );

//         MockOracle fallbackOracle = new MockOracle();
//         poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
//         PoolManager.AssetParams memory params = PoolManager.AssetParams({
//             irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
//             reserveFactor: 0.1 ether,
//             collateralFactor: 0.5 ether
//         });
//         poolManager.setParams("TARGET_PARAMS", params);
//         poolManager.addTarget(address(otherTarget), address(adapter));

//         poolManager.queueSeries(address(adapter), maturity, address(123));
//         (PoolManager.SeriesStatus status, address pool) = PoolManager(address(poolManager)).sSeries(
//             address(adapter),
//             maturity
//         );
//         assertEq(uint256(status), 1); // 1 == QUEUED
//         assertEq(pool, address(123));
//     }

//     /* ========== addSeries() tests ========== */

//     function testAddSeries() public {}

//     /* ========== setParams() tests ========== */

//     function testSetParams() public {}
// }
