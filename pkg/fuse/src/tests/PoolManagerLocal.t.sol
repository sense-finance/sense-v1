// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { CAdapter } from "@sense-finance/v1-core/src/adapters/compound/CAdapter.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { PoolManager } from "../PoolManager.sol";
import { TestHelper } from "@sense-finance/v1-core/src/tests/test-helpers/TestHelper.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { MockFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import { MockOracle } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockOracle.sol";
import { MockComptrollerRejectAdmin, MockComptrollerFailAddMarket } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockFuseDirectory.sol";
import { MockTarget } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import { MockToken } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import { Hevm } from "@sense-finance/v1-core/src/tests/test-helpers/Hevm.sol";
import { DateTimeFull } from "@sense-finance/v1-core/src/tests/test-helpers/DateTimeFull.sol";
import { User } from "@sense-finance/v1-core/src/tests/test-helpers/User.sol";

contract PoolManagerLocalTest is TestHelper {
    using FixedMath for uint256;
    using Errors for string;

    function testDeployPoolManager() public {
        PoolManager pm = new PoolManager(address(1), address(2), address(3), address(4), address(5));
        assertEq(pm.fuseDirectory(), address(1));
        assertEq(pm.comptrollerImpl(), address(2));
        assertEq(pm.cERC20Impl(), address(3));
        assertEq(pm.divider(), address(4));
        assertEq(pm.oracleImpl(), address(5));
        assertTrue(pm.targetOracle() != address(0));
        assertTrue(pm.ptOracle() != address(0));
        assertTrue(pm.lpOracle() != address(0));
        assertTrue(pm.underlyingOracle() != address(0));
    }

    /* ========== deployPool() tests ========== */

    function testCantDeployPoolIfFailToBecomeAdmin() public {
        comptroller = new MockComptrollerRejectAdmin();
        fuseDirectory = new MockFuseDirectory(address(comptroller));
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        try poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(masterOracle)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.FailedBecomeAdmin.selector));
        }
    }

    function testCantDeployPoolIfExists() public {
        try poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(masterOracle)) {
            fail();
        } catch Error(string memory err) {
            assertEq(err, "ERC1167: create2 failed");
        }
    }

    function testDeployPool() public {
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        assertTrue(poolManager.masterOracle() != address(0));
        assertTrue(poolManager.comptroller() != address(0));
    }

    /* ========== addTarget() tests ========== */

    function testCantAddTargetIfPooledNotDeployed() public {
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        try poolManager.addTarget(address(target), address(adapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.PoolNotDeployed.selector));
        }
    }

    function testCantAddTargetIfTargetParamsNotSet() public {
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        try poolManager.addTarget(address(target), address(adapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetParamsNotSet.selector));
        }
    }

    function testCantAddTargetIfFailedToAddMarket() public {
        comptroller = new MockComptrollerFailAddMarket();
        fuseDirectory = new MockFuseDirectory(address(comptroller));
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        try poolManager.addTarget(address(target), address(adapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.FailedAddTargetMarket.selector));
        }
    }

    function testAddTarget() public {
        MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        poolManager.addTarget(address(otherTarget), address(adapter));
    }

    /* ========== queueSeries() tests ========== */

    function testCantQueueSeriesIfPoolNotDeployed() public {
        uint256 maturity = getValidMaturity(2021, 10);
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );
        try poolManager.queueSeries(address(adapter), maturity, address(123)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        }
    }

    function testCantQueueSeriesIfSeriesNotExists() public {
        uint256 maturity = getValidMaturity(2021, 10);
        try poolManager.queueSeries(address(adapter), maturity, address(123)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        }
    }

    function testCantQueueSeriesIfAlreadyQueued() public {
        MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
        uint256 maturity = getValidMaturity(2021, 10);
        divider.setPeriphery(address(this));
        stake.approve(address(divider), type(uint256).max);
        stake.mint(address(this), 1000e18);
        divider.initSeries(address(adapter), maturity, address(alice));

        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );

        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        poolManager.addTarget(address(otherTarget), address(adapter));

        poolManager.queueSeries(address(adapter), maturity, address(123));
        try poolManager.queueSeries(address(adapter), maturity, address(123)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.DuplicateSeries.selector));
        }
    }

    function testQueueSeries() public {
        MockTarget otherTarget = new MockTarget(address(123), "Compound Usdc", "cUSDC", 18);
        uint256 maturity = getValidMaturity(2021, 10);
        divider.setPeriphery(address(this));
        stake.approve(address(divider), type(uint256).max);
        stake.mint(address(this), 1000e18);
        divider.initSeries(address(adapter), maturity, address(alice));
        PoolManager poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(masterOracle) // oracle impl
        );

        MockOracle fallbackOracle = new MockOracle();
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(fallbackOracle));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        poolManager.addTarget(address(otherTarget), address(adapter));

        poolManager.queueSeries(address(adapter), maturity, address(123));
        (PoolManager.SeriesStatus status, address pool) = PoolManager(address(poolManager)).sSeries(
            address(adapter),
            maturity
        );
        assertEq(uint256(status), 1); // 1 == QUEUED
        assertEq(pool, address(123));
    }

    /* ========== addSeries() tests ========== */

    function testAddSeries() public {}

    /* ========== setParams() tests ========== */

    function testSetParams() public {}
}
