// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { DSTest } from "./test-helpers/DSTest.sol";

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { Divider } from "../Divider.sol";
import { CFeed, CTokenInterface } from "../feeds/compound/CFeed.sol";
import { CFactory } from "../feeds/compound/CFactory.sol";
import { BaseTWrapper } from "../wrappers/BaseTWrapper.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { User } from "./test-helpers/User.sol";
import { TestHelper } from "./test-helpers/TestHelper.sol";

contract PeripheryTestHelper is DSTest {
    uint256 public constant DELTA = 1;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address public constant UNI_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant UNI_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    Periphery periphery;
    CFeed feed;
    CFactory internal factory;
    Divider internal divider;

    IUniswapV3Factory uniFactory;
    ISwapRouter uniSwapRouter;

    function setUp() public {
        // periphery
        uniFactory = IUniswapV3Factory(UNI_FACTORY);
        uniSwapRouter = ISwapRouter(uniSwapRouter);
        address poolManager = address(0); // TODO replace for new PoolManager();
        periphery = new Periphery(address(divider), poolManager, address(uniFactory), address(uniSwapRouter));

        // divider
        divider = new Divider(cDAI, address(this));
        divider.setPeriphery(address(periphery));

        // feed & factory
        CFeed implementation = new CFeed(); // compound feed implementation
        BaseTWrapper twImpl = new BaseTWrapper(); // feed implementation
        // deploy compound feed factory
        factory = new CFactory(address(implementation), address(twImpl), address(divider), DELTA, cDAI);
        //        factory.addTarget(cDAI, true);
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        (address f, address wtClone) = factory.deployFeed(cDAI); // deploy a cDAI feed
        feed = CFeed(f);
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
        (address zero, address claim) = periphery.sponsorSeries(address(feed), maturity, 0);

        // check zeros and claim deployed
        assertTrue(zero != address(0));
        assertTrue(claim != address(0));

        // check gclaim deployed
        assertTrue(address(periphery.gClaimManager().gclaims(claim)) != address(0));

        // check Uniswap pool deployed
        assertTrue(uniFactory.getPool(zero, claim, periphery.UNI_POOL_FEE()) != address(0));

        // check zeros and claims onboarded on PoolManager (Fuse)
        // TODO: do when PoolManage ready
    }
}
