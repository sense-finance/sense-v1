// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { Periphery } from "@sense-finance/v1-core/src/Periphery.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { NoopPoolManager } from "../NoopPoolManager.sol";
import { PoolManager } from "../PoolManager.sol";
import { BaseAdapter } from "@sense-finance/v1-core/src/adapters/abstract/BaseAdapter.sol";
import { BaseFactory } from "@sense-finance/v1-core/src/adapters/abstract/factories/BaseFactory.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/test.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import { MockFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import { MockToken } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import { MockTarget } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import { Hevm } from "@sense-finance/v1-core/src/tests/test-helpers/Hevm.sol";
import { DateTimeFull } from "@sense-finance/v1-core/src/tests/test-helpers/DateTimeFull.sol";
import { MockBalancerVault, MockSpaceFactory, MockSpacePool } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockSpace.sol";

contract NoopPoolManagerTest is DSTest {
    using FixedMath for uint256;

    MockToken internal stake;
    MockTarget internal target;
    Divider internal divider;
    Periphery internal periphery;

    TokenHandler internal tokenHandler;
    MockAdapter internal mockAdapter;
    MockFactory internal mockFactory;

    NoopPoolManager internal noopPoolManager;
    PoolManager internal poolManager;

    MockBalancerVault internal balancerVault;
    MockSpaceFactory internal spaceFactory;

    BaseAdapter.AdapterParams internal adapterParams;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x67Db14E73C2Dce786B5bbBfa4D010dEab4BBFCF9;
    address public constant MASTER_ORACLE_IMPL = 0xb3c8eE7309BE658c186F986388c2377da436D8fb;
    address public constant MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE_IMPL);
        noopPoolManager = new NoopPoolManager();

        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));

        periphery = new Periphery(address(divider), address(noopPoolManager), address(spaceFactory), address(balancerVault));

        // Enable the adapter
        divider.setPeriphery(address(this));

        MockToken underlying = new MockToken("Underlying Token", "UD", 18);
        stake = new MockToken("Stake", "SBL", 18);
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

        adapterParams = BaseAdapter.AdapterParams({
            oracle: address(0),
            stake: address(stake),
            stakeSize: 1e18,
            minm: 2 weeks,
            maxm: 14 weeks,
            mode: 0,
            tilt: 0,
            level: 31
        });
        mockAdapter = new MockAdapter(address(divider), address(target), target.underlying(), 0.1e18, adapterParams);

        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: address(0),
            ifee: 0.1e18,
            stakeSize: 1e18,
            minm: 2 weeks,
            maxm: 14 weeks,
            mode: 0,
            tilt: 0,
            guard: 1e18
        });
        mockFactory = new MockFactory(address(divider), factoryParams);

        // Ping scale to set an lscale
        mockAdapter.scale();
        divider.setAdapter(address(mockAdapter), true);

        stake.mint(address(this), 2e18);
        stake.approve(address(periphery), 2e18);
    }

    function testMainnetDeployPoolSucceeds() public {
        uint256 maturity = _getValidMaturity();
        _initSeries(maturity);

        noopPoolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // _Can_ deploy pool twice
        noopPoolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
    }

    function testMainnetAddTargetSucceeds() public {
        // _Can_ add a Target before deploying a pool
        noopPoolManager.addTarget(address(target), address(mockAdapter));

        // Can add a Target after deploying a pool
        noopPoolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // Can now still add Target
        noopPoolManager.addTarget(address(target), address(mockAdapter));

        // Can add same target again
        noopPoolManager.addTarget(address(target), address(mockAdapter));
    }

    function testMainnetQueueSeriesSucceeds() public {
        uint256 maturity = _getValidMaturity();

        // _Can_ queue non-existant Series
        noopPoolManager.queueSeries(address(mockAdapter), maturity, address(0));

        _initSeries(maturity);

        noopPoolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // _Can_ queue if Target has not been added to the pool
        noopPoolManager.queueSeries(address(mockAdapter), maturity, address(0));

        noopPoolManager.addTarget(address(target), address(mockAdapter));
        noopPoolManager.queueSeries(address(mockAdapter), maturity, address(0));
    }

    function testOnboardAdapters() public {
        divider.setPeriphery(address(periphery));

        MockAdapter mockAdapter2 = new MockAdapter(address(divider), address(target), target.underlying(), 0.1e18, adapterParams);
        periphery.onboardAdapter(address(mockAdapter2), true);

        MockAdapter mockAdapter3 = new MockAdapter(address(divider), address(target), target.underlying(), 0.1e18, adapterParams);
        periphery.verifyAdapter(address(mockAdapter3), true);
        periphery.onboardAdapter(address(mockAdapter3), true);

        MockAdapter mockAdapter4 = new MockAdapter(address(divider), address(target), target.underlying(), 0.1e18, adapterParams);
        periphery.verifyAdapter(address(mockAdapter4), true);
        periphery.onboardAdapter(address(mockAdapter4), false);
    }

    event TargetAdded(address indexed, address indexed);

    function testSponsorSeries() public {
        divider.setPeriphery(address(periphery));

        MockAdapter mockAdapter2 = new MockAdapter(address(divider), address(target), target.underlying(), 0.1e18, adapterParams);
        periphery.verifyAdapter(address(mockAdapter2), true);
        periphery.onboardAdapter(address(mockAdapter2), true);

        uint256 maturity = _getValidMaturity();

        periphery.sponsorSeries(address(mockAdapter2), maturity, true);        
    }

    function testFailEmitTargetAdded() public {
        noopPoolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        hevm.expectEmit(true, false, false, false);
        emit TargetAdded(address(target), address(0));

        periphery.verifyAdapter(address(mockAdapter), true);
    }

    // Sanity check with the normal pool manager
    function testEmitNormalPoolManagerTargetAdded() public {
        periphery.setPoolManager(address(poolManager));
        poolManager.setIsTrusted(address(periphery), true);
        PoolManager.AssetParams memory paramsTarget = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether
        });
        poolManager.setParams("TARGET_PARAMS", paramsTarget);

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        hevm.expectEmit(true, false, false, false);
        emit TargetAdded(address(target), address(0));

        periphery.verifyAdapter(address(mockAdapter), true);
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
