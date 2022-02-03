// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { DSTest } from "./test-helpers/DSTest.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";
import { Hevm } from "./test-helpers/Hevm.sol";

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Divider, TokenHandler } from "../Divider.sol";
import { BaseFactory } from "../adapters/BaseFactory.sol";
import { BaseAdapter } from "../adapters/BaseAdapter.sol";
import { CAdapter, CTokenInterface } from "../adapters/compound/CAdapter.sol";
import { CFactory } from "../adapters/compound/CFactory.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";

// Space & Balanacer V2 mock
import { MockSpaceFactory, MockBalancerVault } from "./test-helpers/mocks/MockSpace.sol";

contract PeripheryTestHelper is DSTest, LiquidityHelper {
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    /// @notice Fuse addresses
    address public constant POOL_DIR = 0x835482FE0532f169024d5E9410199369aAD5C77E;
    address public constant COMPTROLLER_IMPL = 0xE16DB319d9dA7Ce40b666DD2E365a4b8B3C18217;
    address public constant CERC20_IMPL = 0x67Db14E73C2Dce786B5bbBfa4D010dEab4BBFCF9;
    address public constant MASTER_ORACLE_IMPL = 0xb3c8eE7309BE658c186F986388c2377da436D8fb;
    address public constant MASTER_ORACLE = 0x1887118E49e0F4A78Bd71B792a49dE03504A764D;

    uint16 public constant MODE = 0;
    uint64 public constant ISSUANCE_FEE = 0.01e18;
    uint256 public constant STAKE_SIZE = 1e18;
    uint48 public constant MIN_MATURITY = 2 weeks;
    uint48 public constant MAX_MATURITY = 14 weeks;

    Periphery internal periphery;
    CAdapter internal adapter;
    CFactory internal factory;
    Divider internal divider;
    PoolManager internal poolManager;
    TokenHandler internal tokenHandler;
    MockOracle internal mockOracle;

    MockBalancerVault internal balancerVault;
    MockSpaceFactory internal spaceFactory;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint48 firstDayOfMonth = uint48(DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0));
        hevm.warp(firstDayOfMonth); // set to first day of the month

        // Divider
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        // Periphery
        poolManager = new PoolManager(POOL_DIR, COMPTROLLER_IMPL, CERC20_IMPL, address(divider), MASTER_ORACLE_IMPL);

        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));

        periphery = new Periphery(
            address(divider),
            address(poolManager),
            address(spaceFactory),
            address(balancerVault)
        );
        poolManager.setIsTrusted(address(periphery), true);
        divider.setPeriphery(address(periphery));

        mockOracle = new MockOracle();

        // Deploy compound adapter factory
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: DAI,
            oracle: address(mockOracle),
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });

        factory = new CFactory(address(divider), factoryParams, COMP);

        divider.setIsTrusted(address(factory), true);
        divider.setIsTrusted(address(factory), true);
        periphery.setFactory(address(factory), true);

        poolManager.deployPool("Sense Pool", 0.051 ether, 1 ether, MASTER_ORACLE);
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);
    }
}

contract PeripheryTests is PeripheryTestHelper {
    using FixedMath for uint256;

    function testMainnetSponsorSeries() public {
        address f = periphery.onboardAdapter(address(factory), cDAI);
        adapter = CAdapter(payable(f));
        // Mint this address MAX_UINT DAI
        giveTokens(DAI, type(uint256).max, hevm);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint48 maturity = uint48(
            DateTimeFull.timestampFromDateTime(month == 12 ? year + 1 : year, month == 12 ? 1 : (month + 1), 1, 0, 0, 0)
        );

        ERC20(DAI).approve(address(periphery), type(uint256).max);
        (address zero, address claim) = periphery.sponsorSeries(address(adapter), maturity);

        // Check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // Check zeros and claims onboarded on PoolManager (Fuse)
        assertTrue(poolManager.sStatus(address(adapter), maturity) == PoolManager.SeriesStatus.QUEUED);
    }
}
