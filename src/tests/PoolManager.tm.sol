// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { FixedMath } from "../external/FixedMath.sol";

// Internal references
import { Divider, AssetDeployer } from "../Divider.sol";
import { CAdapter, CTokenInterface } from "../adapters/compound/CAdapter.sol";
import { Token } from "../tokens/Token.sol";
import { PoolManager } from "../fuse/PoolManager.sol";

import { DSTest } from "./test-helpers/DSTest.sol";
import { MockFactory } from "./test-helpers/mocks/MockFactory.sol";
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { SimpleAdminAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { Hevm } from "./test-helpers/Hevm.sol";
import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";

contract PoolManagerTest is DSTest {
    using FixedMath for uint256;

    Token internal stake;
    Token internal target;
    Divider internal divider;
    AssetDeployer internal assetDeployer;
    SimpleAdminAdapter internal adminAdapter;
    MockOracle internal mockOracle;

    PoolManager internal poolManager;

    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x2b3dD0AE288c13a730F6C422e2262a9d3dA79Ed1;
    address public constant MASTER_ORACLE_FALLBACK = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    function setUp() public {
        stake = new Token("Stake", "SBL", 18, address(this));
        assetDeployer = new AssetDeployer();
        divider = new Divider(address(this), address(assetDeployer));
        assetDeployer.init(address(divider));

        target = new Token("Target", "TGT", 18, address(this));
        mockOracle = new MockOracle();
        adminAdapter = new SimpleAdminAdapter(address(target), "Admin", "ADM");

        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE_FALLBACK);

        // Enable the adapter
        divider.setAdapter(address(adminAdapter), true);
        // Give this address periphery access to the divider (so that it can create Series)
        divider.setPeriphery(address(this));
    }

    function initSeries() public returns (uint256 _maturity) {
        // Setup mock stake token
        stake.mint(address(this), 1000 ether);
        stake.approve(address(divider), 1000 ether);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp + 10 weeks);
        _maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        divider.initSeries(address(adminAdapter), _maturity, address(this));
    }

    function testDeployPool() public {
        initSeries();

        assertTrue(poolManager.comptroller() == address(0));
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE_FALLBACK);

        assertTrue(poolManager.comptroller() != address(0));
    }

    function testAddTarget() public {
        uint256 maturity = initSeries();
        // Cannot add a Target before deploying a pool
        try poolManager.addTarget(address(target)) {
            fail();
        } catch Error(string memory error) {
            assertEq(error, "Pool not yet deployed");
        }

        // Can add a Target after deploying a pool
        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE_FALLBACK);

        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
        poolManager.addTarget(address(target)) ;

        // assert
        assertTrue(false);
    }
}
