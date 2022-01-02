// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { DSTest } from "./test-helpers/DSTest.sol";
import { Hevm } from "./test-helpers/Hevm.sol";

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Divider, TokenHandler } from "../Divider.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
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

    uint8 public constant MODE = 0;
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
    TokenHandler internal tokenHandler;

    IUniswapV3Factory uniFactory;
    ISwapRouter uniSwapRouter;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint48 firstDayOfMonth = uint48(DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0));
        hevm.warp(firstDayOfMonth); // set to first day of the month

        // divider
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        // periphery
        uniFactory = IUniswapV3Factory(UNI_FACTORY);
        uniSwapRouter = ISwapRouter(uniSwapRouter);
        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE);
        periphery = new Periphery(address(divider), address(poolManager), address(uniFactory), address(uniSwapRouter));
        poolManager.setIsTrusted(address(periphery), true);
        divider.setPeriphery(address(periphery));

        // adapter & factory

        // deploy compound adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: DAI,
            oracle: MASTER_ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });

        factory = new CFactory(address(divider), factoryParams, COMP);

        divider.setIsTrusted(address(factory), true); // TODO: remove when Space ready
        address f = factory.deployAdapter(cDAI); // TODO: remove when Space ready
        // divider.setIsTrusted(address(factory), true); // TODO: uncomment when Space ready
        // periphery.setFactory(address(factory), true); // TODO: uncomment when Space ready
        // onboard adapter, target wrapper
        // address f = periphery.onboardAdapter(address(factory), cDAI); // onboard target through Periphery // TODO: uncomment when Space ready
        adapter = CAdapter(payable(f));
    }
}

contract PeripheryTests is PeripheryTestHelper {
    using FixedMath for uint256;

    function testMainnetSponsorSeries() public {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint48 maturity = uint48(
            DateTimeFull.timestampFromDateTime(year, (month + 1) == 13 ? 1 : (month + 1), 1, 0, 0, 0)
        );

        ERC20(DAI).approve(address(periphery), 2**256 - 1);
        (address zero, address claim) = periphery.sponsorSeries(address(adapter), maturity);

        // check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // TODO: uncomment below lines when Space ready

        // // check Balancer pool deployed
        // assertTrue(address(spaceFactory.pool()) != address(0));

        // // check zeros and claims onboarded on PoolManager (Fuse)
        // assertTrue(poolManager.sStatus(address(adapter), maturity) == PoolManager.SeriesStatus.QUEUED);
    }
}
