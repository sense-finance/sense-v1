// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { CAdapter, CTokenInterface } from "@sense-finance/v1-core/src/adapters/compound/CAdapter.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { PoolManager } from "../PoolManager.sol";
import { BaseAdapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { MockFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import { MockOracle } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockOracle.sol";
import { MockTarget } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import { MockToken } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import { Hevm } from "@sense-finance/v1-core/src/tests/test-helpers/Hevm.sol";
import { DateTimeFull } from "@sense-finance/v1-core/src/tests/test-helpers/DateTimeFull.sol";
import { User } from "@sense-finance/v1-core/src/tests/test-helpers/User.sol";
import { MockBalancerVault, MockSpaceFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockSpace.sol";

contract PoolManagerTest is DSTest {
    using FixedMath for uint256;

    MockToken internal stake;
    MockTarget internal target;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    MockAdapter internal mockAdapter;
    MockOracle internal mockOracle;

    PoolManager internal poolManager;

    MockBalancerVault internal balancerVault;
    MockSpaceFactory internal spaceFactory;

    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x67Db14E73C2Dce786B5bbBfa4D010dEab4BBFCF9;
    address public constant MASTER_ORACLE_IMPL = 0xb3c8eE7309BE658c186F986388c2377da436D8fb;
    address public constant MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));
        mockOracle = new MockOracle();

        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE_IMPL);

        // Enable the adapter
        divider.setPeriphery(address(this));

        MockToken underlying = new MockToken("Underlying Token", "UD", 18);
        MockToken reward = new MockToken("Reward Token", "RT", 18);
        stake = new MockToken("Stake", "SBL", 18);
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

        mockAdapter = new MockAdapter(
            address(divider),
            address(target),
            address(mockOracle),
            0.1e18,
            address(stake),
            1e18,
            2 weeks,
            14 weeks,
            0,
            0,
            31,
            address(reward)
        );

        // Ping scale to set an lscale
        mockAdapter.scale();
        divider.setAdapter(address(mockAdapter), true);

        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));
    }

    function testMainnetDeployPool() public {
        uint256 maturity = _getValidMaturity();
        _initSeries(maturity);

        assertTrue(poolManager.comptroller() == address(0));
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        assertTrue(poolManager.comptroller() != address(0));

        // Can't deploy pool twice
        try poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE) {
            fail();
        } catch Error(string memory err) {
            assertEq(err, "ERC1167: create2 failed");
        }
    }

    function testMainnetAddTarget() public {
        // Cannot add a Target before deploying a pool
        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.PoolNotDeployed.selector));
        }

        // Can add a Target after deploying a pool
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // Cannot add a Target before params have been set
        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetParamsNotSet.selector));
        }

        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // Can now add Target
        poolManager.addTarget(address(target), address(mockAdapter));

        assertTrue(poolManager.tInits(address(target)));

        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetExists.selector));
        }
    }

    function testMainnetQueueSeries() public {
        uint256 maturity = _getValidMaturity();

        // Cannot queue non-existant Series
        try poolManager.queueSeries(address(mockAdapter), maturity, address(0)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesDoesNotExist.selector));
        }

        _initSeries(maturity);

        // Cannot queue if the Target has not been deployed in Fuse
        try poolManager.queueSeries(address(mockAdapter), maturity, address(0)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetNotInFuse.selector));
        }

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        poolManager.addTarget(address(target), address(mockAdapter));

        poolManager.queueSeries(address(mockAdapter), maturity, address(0));
    }

    function testMainnetAddSeries() public {
        uint256 maturity = _getValidMaturity();
        _initSeries(maturity);

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
        PoolManager.AssetParams memory paramsTarget = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", paramsTarget);
        poolManager.addTarget(address(target), address(mockAdapter));

        address pool = spaceFactory.create(address(mockAdapter), maturity);

        // Cannot add Series if it hasn't been queued
        try poolManager.addSeries(address(mockAdapter), maturity) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.SeriesNotQueued.selector));
        }

        poolManager.queueSeries(address(mockAdapter), maturity, pool);

        // Cannot add Series if params aren't set
        try poolManager.addSeries(address(mockAdapter), maturity) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.ZeroParamsNotSet.selector));
        }

        poolManager.setParams(
            "ZERO_PARAMS",
            PoolManager.AssetParams({
                irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
                reserveFactor: 0.1 ether,
                collateralFactor: 0.5 ether,
                closeFactor: 0.051 ether,
                liquidationIncentive: 1 ether
            })
        );

        try poolManager.addSeries(address(mockAdapter), maturity) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.PoolParamsNotSet.selector));
        }

        // TODO(josh): finish mainnet test when the oracle is ready
        // poolManager.setParams(
        //     "LP_TOKEN_PARAMS",
        //     PoolManager.AssetParams({
        //         irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
        //         reserveFactor: 0.1 ether,
        //         collateralFactor: 0.5 ether,
        //         closeFactor: 0.051 ether,
        //         liquidationIncentive: 1 ether
        //     })
        // );

        // poolManager.addSeries(address(mockAdapter), maturity);
    }

    function _getValidMaturity() internal view returns (uint256 maturity) {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp + 10 weeks);
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
    }

    function _initSeries(uint256 maturity) internal {
        // Setup mock stake token
        stake.mint(address(this), 1000 ether);
        stake.approve(address(divider), 1000 ether);

        divider.initSeries(address(mockAdapter), maturity, address(this));
    }
}
