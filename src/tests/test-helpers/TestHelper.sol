// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { GClaimManager } from "../../modules/GClaimManager.sol";
import { Divider, AssetDeployer } from "../../Divider.sol";
import { PoolManager } from "../../fuse/PoolManager.sol";
import { Token } from "../../tokens/Token.sol";
import { Periphery } from "../../Periphery.sol";
import { MockTWrapper } from "./mocks/MockTWrapper.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockFeed } from "./mocks/MockFeed.sol";
import { MockFactory } from "./mocks/MockFactory.sol";

// Uniswap mocks
import { MockUniFactory } from "./mocks/uniswap/MockUniFactory.sol";
import { MockUniSwapRouter } from "./mocks/uniswap/MockUniSwapRouter.sol";

// Fuse & compound mocks
import { MockComptroller } from "./mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "./mocks/fuse/MockFuseDirectory.sol";

import { DSTest } from "./DSTest.sol";
import { Hevm } from "./Hevm.sol";
import { DateTimeFull } from "./DateTimeFull.sol";
import { User } from "./User.sol";
import { FixedMath } from "../../external/FixedMath.sol";

contract TestHelper is DSTest {
    using FixedMath for uint256;

    MockFeed feed;
    MockToken stable;
    MockToken target;
    MockToken reward;
    MockFactory factory;
    MockTWrapper internal twrapper;

    PoolManager poolManager;
    Divider internal divider;
    AssetDeployer internal assetDeployer;
    Periphery internal periphery;

    User internal alice;
    User internal bob;
    User internal jim;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    //uniswap
    MockUniFactory uniFactory;
    MockUniSwapRouter uniSwapRouter;

    // fuse & compound
    MockComptroller comptroller;
    MockFuseDirectory fuseDirectory;

    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 internal DELTA = 800672247590; // GROWTH_PER_SECOND + 1% = 25.25% APY

    uint256 public ISSUANCE_FEE;
    uint256 public INIT_STAKE;
    uint public SPONSOR_WINDOW;
    uint public SETTLEMENT_WINDOW;
    uint public MIN_MATURITY;
    uint public MAX_MATURITY;

    struct Series {
        address zero; // Zero address for this Series (deployed on Series initialization)
        address claim; // Claim address for this Series (deployed on Series initialization)
        address sponsor; // Series initializer/sponsor
        uint256 issuance; // Issuance date for this Series (needed for Zero redemption)
        uint256 reward; // Tracks the fees due to the settler on Settlement
        uint256 iscale; // Scale value at issuance
        uint256 mscale; // Scale value at maturity
        uint256 stake; // Balance staked at initialisation TODO: do we want to keep this?
        address stable; // Address of the stable stake token TODO: do we want to keep this?
    }

    function setUp() public {
        hevm.warp(1630454400);
        // 01-09-21 00:00 UTC
        uint8 tDecimals = 18;
        stable = new MockToken("Stable Token", "ST", tDecimals);
        target = new MockToken("Compound Dai", "cDAI", tDecimals);
        reward = new MockToken("Reward Token", "RT", tDecimals);
        uint256 base = convertBase(target.decimals());
        GROWTH_PER_SECOND = tDecimals > 18 ? GROWTH_PER_SECOND * base : GROWTH_PER_SECOND / base;
        DELTA = tDecimals > 18 ? DELTA * base : DELTA / base;

        // divider
        assetDeployer = new AssetDeployer();
        divider = new Divider(address(stable), address(this), address(assetDeployer));
        assetDeployer.init(address(divider));
        divider.setGuard(address(target), 10*2**96);

        ISSUANCE_FEE = divider.ISSUANCE_FEE();
        INIT_STAKE = divider.INIT_STAKE();
        SPONSOR_WINDOW = divider.SPONSOR_WINDOW();
        SETTLEMENT_WINDOW = divider.SETTLEMENT_WINDOW();
        MIN_MATURITY = divider.MIN_MATURITY();
        MAX_MATURITY = divider.MAX_MATURITY();

        // uniswap mocks
        uniFactory = new MockUniFactory();
        uniSwapRouter = new MockUniSwapRouter();

        // fuse & comp mocks
        comptroller = new MockComptroller();
        fuseDirectory = new MockFuseDirectory(address(comptroller));

        // pool manager
        poolManager = new PoolManager(address(fuseDirectory), address(comptroller), address(1), address(divider), address(1));
        poolManager.deployPool("Sense Fuse Pool", false, 0.051 ether, 1 ether);
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // periphery
        periphery = new Periphery(address(divider), address(poolManager), address(uniFactory), address(uniSwapRouter));
        divider.setPeriphery(address(periphery));
        poolManager.setPeriphery(address(periphery));

        // feed, target wrapper & factory
        MockFeed feedImpl = new MockFeed(); // feed implementation
        MockTWrapper twImpl = new MockTWrapper(); // feed implementation
        factory = new MockFactory(address(feedImpl), address(twImpl), address(divider), DELTA, address(reward)); // deploy feed factory
        factory.addTarget(address(target), true); // make mock factory support target
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        periphery.setFactory(address(factory), true);
        (address f, address wt) = periphery.onboardTarget(address(factory), address(target)); // onboard target through Periphery
        feed = MockFeed(f);
        twrapper = MockTWrapper(wt);

        // users
        alice = createUser(2**96, 2**96);
        bob = createUser(2**96, 2**96);
        jim = createUser(2**96, 2**96);
    }

    function createUser(uint256 tBal, uint256 sBal) public returns (User user) {
        user = new User();
        user.setFactory(factory);
        user.setStable(stable);
        user.setTarget(target);
        user.setDivider(divider);
        user.setPeriphery(periphery);
        user.doApprove(address(stable), address(periphery));
        user.doApprove(address(stable), address(divider));
        user.doMint(address(stable), sBal);
        user.doApprove(address(target), address(periphery));
        user.doApprove(address(target), address(divider));
        user.doApprove(address(target), address(periphery.gClaimManager()));
        user.doMint(address(target), tBal);
    }

    function createFactory(address _target, address _reward) public returns (MockFactory someFactory) {
        MockFeed feedImpl = new MockFeed();
        MockTWrapper twImpl = new MockTWrapper();
        someFactory = new MockFactory(address(feedImpl), address(twImpl), address(divider), DELTA, address(_reward));
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);
    }

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint256 maturity) {
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        require(maturity >= block.timestamp + 2 weeks, "Maturity must be 2 weeks from current timestamp");
    }

    function sponsorSampleSeries(address sponsor, uint256 maturity) public returns (address zero, address claim) {
        (zero, claim) = User(sponsor).doSponsorSeries(address(feed), maturity);
    }

    function assertClose(uint256 actual, uint256 expected) public {
        if (actual == expected) return DSTest.assertEq(actual, expected);
        uint256 variance = 100;
        if (expected < variance) variance = 10;
        if (expected < variance) variance = 1;
        DSTest.assertTrue(actual >= (expected - variance));
        DSTest.assertTrue(actual <= (expected + variance));
    }

    function addLiquidityToUniSwapRouter(uint256 maturity, address zero, address claim) public {
        uint256 cBal = MockToken(claim).balanceOf(address(alice));
        uint256 zBal = MockToken(zero).balanceOf(address(alice));
        alice.doIssue(address(feed), maturity, 100e18);
        uint256 cBalIssued = MockToken(claim).balanceOf(address(alice)) - cBal;
        uint256 zBalIssued = MockToken(zero).balanceOf(address(alice)) - zBal;
        alice.doApprove(address(claim), address(periphery.gClaimManager()));
        alice.doApprove(address(zero), address(periphery.gClaimManager()));
        alice.doJoin(address(feed), maturity, cBalIssued);
        address gclaim = address(periphery.gClaimManager().gclaims(claim));
        alice.doTransfer(gclaim, address(uniSwapRouter), cBalIssued);
        alice.doTransfer(zero, address(uniSwapRouter), zBalIssued);
    }

    function convertBase(uint256 decimals) public returns (uint256) {
        uint256 base = 1;
        if (decimals != 18) {
            base = decimals > 18 ? 10 ** (decimals - 18) : 10 ** (18 - decimals);
        }
        return base;
    }

    function calculateAmountToIssue(uint256 tBal, uint256 maturity, uint256 baseUnit) public returns (uint256 toIssue) {
        (, uint256 cscale) = feed.lscale();
//        uint256 cscale = divider.lscales(address(feed), maturity, address(bob));
        toIssue = tBal.fmul(cscale, baseUnit);
    }

    function calculateExcess(uint256 tBal, uint256 maturity, address claim) public returns (uint256 gap){
        uint256 toIssue = calculateAmountToIssue(tBal, maturity, Token(claim).BASE_UNIT());
        gap = periphery.gClaimManager().excess(address(feed), maturity, toIssue);
    }

}
