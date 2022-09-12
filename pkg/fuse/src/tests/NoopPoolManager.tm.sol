// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { NoopPoolManager } from "../NoopPoolManager.sol";
import { BaseAdapter } from "@sense-finance/v1-core/src/adapters/abstract/BaseAdapter.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/test.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
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
    TokenHandler internal tokenHandler;
    MockAdapter internal mockAdapter;

    NoopPoolManager internal poolManager;

    MockBalancerVault internal balancerVault;
    MockSpaceFactory internal spaceFactory;

    address internal constant MASTER_ORACLE = address(0);

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        poolManager = new NoopPoolManager();

        // Enable the adapter
        divider.setPeriphery(address(this));

        MockToken underlying = new MockToken("Underlying Token", "UD", 18);
        stake = new MockToken("Stake", "SBL", 18);
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", 18);

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
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

        // Ping scale to set an lscale
        mockAdapter.scale();
        divider.setAdapter(address(mockAdapter), true);

        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));
    }

    function testMainnetDeployPoolSucceeds() public {
        uint256 maturity = _getValidMaturity();
        _initSeries(maturity);

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // _Can_ deploy pool twice
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
    }

    function testMainnetAddTargetSucceeds() public {
        // _Can_ add a Target before deploying a pool
        poolManager.addTarget(address(target), address(mockAdapter));

        // Can add a Target after deploying a pool
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // Can now still add Target
        poolManager.addTarget(address(target), address(mockAdapter));

        // Can add same target again
        poolManager.addTarget(address(target), address(mockAdapter));
    }

    function testMainnetQueueSeriesSucceeds() public {
        uint256 maturity = _getValidMaturity();

        // _Can_ queue non-existant Series
        poolManager.queueSeries(address(mockAdapter), maturity, address(0));

        _initSeries(maturity);

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // _Can_ queue if Target has not been added to the pool
        poolManager.queueSeries(address(mockAdapter), maturity, address(0));

        poolManager.addTarget(address(target), address(mockAdapter));
        poolManager.queueSeries(address(mockAdapter), maturity, address(0));
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
