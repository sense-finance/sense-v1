// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { DSTest } from "./test-helpers/DSTest.sol";

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "../fuse/PoolManager.sol";
import { Divider, AssetDeployer } from "../Divider.sol";
import { CAdapter, CTokenInterface } from "../adapters/compound/CAdapter.sol";
import { CFactory } from "../adapters/compound/CFactory.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract PeripheryTestHelper is DSTest {
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant UNI_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNI_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x2b3dD0AE288c13a730F6C422e2262a9d3dA79Ed1;
    address public constant MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    uint256 public constant DELTA = 1;
    uint256 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint256 public constant MIN_MATURITY = 2 weeks;
    uint256 public constant MAX_MATURITY = 14 weeks;

    Periphery periphery;
    CAdapter adapter;
    CFactory internal factory;
    Divider internal divider;
    PoolManager internal poolManager;
    AssetDeployer internal assetDeployer;

    IUniswapV3Factory uniFactory;
    ISwapRouter uniSwapRouter;

    function setUp() public {
        // periphery
        uniFactory = IUniswapV3Factory(UNI_FACTORY);
        uniSwapRouter = ISwapRouter(uniSwapRouter);
        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE);
        periphery = new Periphery(address(divider), address(poolManager), address(uniFactory), address(uniSwapRouter));
        poolManager.setIsTrusted(address(periphery), true);

        // divider
        assetDeployer = new AssetDeployer();
        divider = new Divider(address(this), address(assetDeployer));
        assetDeployer.init(address(divider));
        divider.setPeriphery(address(periphery));

        // adapter & factory
        CAdapter implementation = new CAdapter(); // compound adapter implementation

        // deploy compound adapter factory
        factory = new CFactory(
            address(divider),
            address(implementation),
            DAI,
            STAKE_SIZE,
            ISSUANCE_FEE,
            MIN_MATURITY,
            MAX_MATURITY,
            DELTA,
            COMP
        );
        //        factory.addTarget(cDAI, true);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        address f = factory.deployAdapter(cDAI); // deploy a cDAI adapter
        adapter = CAdapter(f);
        // users
        //        alice = createUser(2**96, 2**96);
        //        bob = createUser(2**96, 2**96);
    }
}

contract PeripheryTests is PeripheryTestHelper {
    using FixedMath for uint256;

    function testSponsorSeries() public {
        TestHelper th = new TestHelper();
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        if (maturity >= block.timestamp + 2 weeks) {
            maturity = DateTimeFull.timestampFromDateTime(year, month + 1 == 13 ? 1 : month + 1, 1, 0, 0, 0);
        }
        ERC20(cDAI).approve(address(periphery), 2**256 - 1);
        (address zero, address claim) = periphery.sponsorSeries(address(adapter), maturity, 0);

        // check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // check Uniswap pool deployed
        assertTrue(uniFactory.getPool(zero, claim, periphery.UNI_POOL_FEE()) != address(0));

        // check zeros and claims onboarded on PoolManager (Fuse)
        // TODO: do when PoolManage ready
    }
}
