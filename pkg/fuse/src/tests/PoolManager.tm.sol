// SPDX-License-Identifier: UNLICENSED
pragma solidity  0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { CAdapter, CTokenInterface } from "@sense-finance/v1-core/src/adapters/compound/CAdapter.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { PoolManager } from "../PoolManager.sol";
import { BaseAdapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/DSTest.sol";
import { MockFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import { MockOracle } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockOracle.sol";
import { MockTarget } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import { MockToken } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import { Hevm } from "@sense-finance/v1-core/src/tests/test-helpers/Hevm.sol";
import { DateTimeFull } from "@sense-finance/v1-core/src/tests/test-helpers/DateTimeFull.sol";
import { User } from "@sense-finance/v1-core/src/tests/test-helpers/User.sol";

contract PoolManagerTest is DSTest {
    using FixedMath for uint256;

    MockToken internal stake;
    MockTarget internal target;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    MockAdapter internal mockAdapter;
    MockOracle internal mockOracle;

    PoolManager internal poolManager;

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
        mockAdapter = new MockAdapter();

        MockToken underlying = new MockToken("Underlying Token", "UD", 18);
        MockToken reward = new MockToken("Reward Token", "RT", 18);
        stake = new MockToken("Stake", "SBL", 18);
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            target: address(target),
            delta: 150,
            oracle: address(mockOracle),
            ifee: 0.1e18,
            stake: address(stake),
            stakeSize: 1e18,
            minm: 2 weeks,
            maxm: 14 weeks,
            mode: 0
        });

        mockAdapter.initialize(address(divider), adapterParams, address(reward));
        // Ping scale to set an lscale
        mockAdapter.scale();
        divider.setAdapter(address(mockAdapter), true);
    }

    function initSeries() public returns (uint48 _maturity) {
        // Setup mock stake token
        stake.mint(address(this), 1000 ether);
        stake.approve(address(divider), 1000 ether);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp + 10 weeks);
        _maturity = uint48(DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0));
        divider.initSeries(address(mockAdapter), _maturity, address(this));
    }

    function testMainnetDeployPool() public {
        initSeries();

        assertTrue(poolManager.comptroller() == address(0));
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        assertTrue(poolManager.comptroller() != address(0));
    }

    function testMainnetAddTarget() public {
        // Cannot add a Target before deploying a pool
        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "Pool not yet deployed");
        }

        // Can add a Target after deploying a pool
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

        assertTrue(poolManager.tInits(address(target)));
    }
}
