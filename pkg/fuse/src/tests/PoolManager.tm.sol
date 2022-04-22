// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// Internal references
import { FixedMath } from "@sense-finance/v1-core/src/external/FixedMath.sol";
import { Divider, TokenHandler } from "@sense-finance/v1-core/src/Divider.sol";
import { CAdapter } from "@sense-finance/v1-core/src/adapters/compound/CAdapter.sol";
import { CToken } from "@sense-finance/v1-fuse/src/external/CToken.sol";
import { Token } from "@sense-finance/v1-core/src/tokens/Token.sol";
import { PoolManager, MasterOracleLike } from "../PoolManager.sol";
import { BaseAdapter } from "@sense-finance/v1-core/src/adapters/BaseAdapter.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { DSTest } from "@sense-finance/v1-core/src/tests/test-helpers/test.sol";
import { MockFactory } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockFactory.sol";
import { MockOracle } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/fuse/MockOracle.sol";
import { MockTarget } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockTarget.sol";
import { MockToken } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockAdapter.sol";
import { Hevm } from "@sense-finance/v1-core/src/tests/test-helpers/Hevm.sol";
import { DateTimeFull } from "@sense-finance/v1-core/src/tests/test-helpers/DateTimeFull.sol";
import { User } from "@sense-finance/v1-core/src/tests/test-helpers/User.sol";
import { MockBalancerVault, MockSpaceFactory, MockSpacePool } from "@sense-finance/v1-core/src/tests/test-helpers/mocks/MockSpace.sol";
import { PriceOracle } from "../external/PriceOracle.sol";

interface ComptrollerLike {
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);

    function cTokensByUnderlying(address underlying) external view returns (address);

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (uint256);

    struct Market {
        bool isListed;
        uint256 collateralFactorMantissa;
    }

    function markets(address cToken) external view returns (Market memory);
}

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
    
    uint256 public DEFAULT_TS = FixedMath.WAD.fdiv(FixedMath.WAD * 31622400); // 1 / 1 year in seconds;
    uint256 public DEFAULT_G1 = (FixedMath.WAD * 950).fdiv(FixedMath.WAD * 1000); // 0.95 for selling underlying
    uint256 public DEFAULT_G2 = (FixedMath.WAD * 1000).fdiv(FixedMath.WAD * 950); // 1 / 0.95 for selling PT

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

        BaseAdapter.AdapterParams memory adapterParams = BaseAdapter.AdapterParams({
            oracle: address(mockOracle),
            stake: address(stake),
            stakeSize: 1e18,
            minm: 2 weeks,
            maxm: 14 weeks,
            mode: 0,
            tilt: 0,
            level: 31,
            ts: DEFAULT_TS,
            g1: DEFAULT_G1,
            g2: DEFAULT_G2,
            oracleEnabled: true
        });
        mockAdapter = new MockAdapter(
            address(divider),
            address(target),
            target.underlying(),
            0.1e18,
            adapterParams,
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
            collateralFactor: 0.5 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // Can now add Target
        poolManager.addTarget(address(target), address(mockAdapter));

        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, hex"");
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

        // Cannot queue if the Fuse pool has not been deployed (no comptroller)
        try poolManager.queueSeries(address(mockAdapter), maturity, address(0)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, hex"");
        }

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);

        // Cannot queue if Target has not been added to the Fuse pool
        try poolManager.queueSeries(address(mockAdapter), maturity, address(0)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, abi.encodeWithSelector(Errors.TargetNotInFuse.selector));
        }

        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether
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
            collateralFactor: 0.5 ether
        });
        poolManager.setParams("TARGET_PARAMS", paramsTarget);
        address cTarget = poolManager.addTarget(address(target), address(mockAdapter));

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
            assertEq0(error, abi.encodeWithSelector(Errors.PTParamsNotSet.selector));
        }

        poolManager.setParams(
            "PT_PARAMS",
            PoolManager.AssetParams({
                irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
                reserveFactor: 0.1 ether,
                collateralFactor: 0.5 ether
            })
        );

        poolManager.setParams(
            "LP_TOKEN_PARAMS",
            PoolManager.AssetParams({
                irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
                reserveFactor: 0.1 ether,
                collateralFactor: 0.5 ether
            })
        );

        (address cPT, address cLPToken) = poolManager.addSeries(address(mockAdapter), maturity);
        ComptrollerLike comptroller = ComptrollerLike(poolManager.comptroller());

        assertTrue(cPT != address(0));
        assertTrue(cLPToken != address(0));

        address[] memory cTokens = new address[](3);
        cTokens[0] = address(cTarget);
        cTokens[1] = address(cPT);
        cTokens[2] = address(cLPToken);

        ComptrollerLike(comptroller).enterMarkets(cTokens);

        uint256 TARGET_IN = 1.1e18;

        // Mint some liquidity for lending/borrowing
        Token(MockSpacePool(pool).target()).mint(address(balancerVault), 1e18);
        MockSpacePool(pool).mint(address(this), 1e18);

        target.mint(address(this), TARGET_IN);
        target.approve(cTarget, TARGET_IN);
        uint256 originalTargetBalance = target.balanceOf(address(this));
        uint256 err = CToken(cTarget).mint(TARGET_IN);
        assertEq(err, 0);

        // Has the initial Target's value in cTarget
        assertEq(
            (Token(cTarget).balanceOf(address(this)) * CToken(cTarget).exchangeRateCurrent()) /
                10**CToken(cTarget).decimals(),
            TARGET_IN
        );

        err = ComptrollerLike(comptroller).borrowAllowed(address(cPT), address(this), 1e18);
        // Insufficient liquidity
        assertEq(err, 4);

        Hevm(HEVM_ADDRESS).expectRevert("borrow is paused");
        ComptrollerLike(comptroller).borrowAllowed(address(cLPToken), address(this), 1e18);

        err = CToken(cTarget).redeem(Token(cTarget).balanceOf(address(this)));
        assertEq(err, 0);
        assertEq(target.balanceOf(address(this)), originalTargetBalance);
    }

    function testMainnetAdminPassthrough() public {
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // re-create add target

        address underlying = mockAdapter.underlying();

        address[] memory underlyings = new address[](2);
        underlyings[0] = address(target);
        underlyings[1] = underlying;

        PriceOracle[] memory oracles = new PriceOracle[](2);
        oracles[0] = PriceOracle(poolManager.targetOracle());
        oracles[1] = PriceOracle(poolManager.masterOracle());

        poolManager.execute(
            poolManager.underlyingOracle(),
            0,
            abi.encodeWithSignature("setUnderlying(address,address)", underlying, address(mockAdapter)),
            gasleft() - 100000
        );
        poolManager.execute(
            poolManager.targetOracle(),
            0,
            abi.encodeWithSignature("setTarget(address,address)", address(target), address(mockAdapter)),
            gasleft() - 100000
        );

        poolManager.execute(
            poolManager.masterOracle(),
            0,
            abi.encodeWithSignature("add(address[],address[])", underlyings, oracles),
            gasleft() - 100000
        );

        bytes memory constructorData = abi.encode(
            target,
            poolManager.comptroller(),
            0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            target.name(),
            target.symbol(),
            poolManager.cERC20Impl(),
            hex"", // calldata sent to becomeImplementation (empty bytes b/c it's currently unused)
            0.1 ether,
            0 // no admin fee
        );

        // Can now add Target with the passthrough
        bool success = poolManager.execute(
            poolManager.comptroller(),
            0,
            abi.encodeWithSignature("_deployMarket(bool,bytes,uint256)", false, constructorData, 0.5 ether),
            gasleft() - 100000
        );
        assertTrue(success);

        // shouldn't be able to add target again
        try poolManager.addTarget(address(target), address(mockAdapter)) {
            fail();
        } catch (bytes memory error) {
            assertEq0(error, hex"");
        }

        address cTarget = ComptrollerLike(poolManager.comptroller()).cTokensByUnderlying(address(target));

        Hevm(HEVM_ADDRESS).roll(1);

        success = poolManager.execute(
            poolManager.comptroller(),
            0,
            abi.encodeWithSignature("_unsupportMarket(address)", cTarget),
            gasleft() - 100000
        );
        assertTrue(success);

        // should be able to add target again after it's been un-supported
        poolManager.addTarget(address(target), address(mockAdapter));
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
