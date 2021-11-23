// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// Internal references
import { GClaimManager } from "../../modules/GClaimManager.sol";
import { Divider, TokenHandler } from "../../Divider.sol";
import { BaseFactory } from "../../adapters/BaseFactory.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Token } from "../../tokens/Token.sol";
import { Periphery } from "../../Periphery.sol";
import { MockToken } from "./mocks/MockToken.sol";
import { MockTarget } from "./mocks/MockTarget.sol";
import { MockAdapter } from "./mocks/MockAdapter.sol";
import { MockFactory } from "./mocks/MockFactory.sol";

// Space & Balanacer V2 mock
import { MockSpaceFactory, MockBalancerVault } from "./mocks/Space.sol";

// Fuse & compound mocks
import { MockComptroller } from "./mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "./mocks/fuse/MockFuseDirectory.sol";
import { MockOracle } from "./mocks/fuse/MockOracle.sol";

import { DSTest } from "./DSTest.sol";
import { Hevm } from "./Hevm.sol";
import { DateTimeFull } from "./DateTimeFull.sol";
import { User } from "./User.sol";
import { FixedMath } from "../../external/FixedMath.sol";

contract TestHelper is DSTest {
    using FixedMath for uint256;

    MockAdapter adapter;
    MockToken stake;
    MockToken underlying;
    MockTarget target;
    MockToken reward;
    MockFactory factory;
    MockOracle masterOracle;

    PoolManager poolManager;
    GClaimManager gClaimManager;
    Divider internal divider;
    TokenHandler internal tokenHandler;
    Periphery internal periphery;

    User internal alice;
    User internal bob;
    User internal jim;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    // balancer/space
    MockSpaceFactory spaceFactory;
    MockBalancerVault balancerVault;

    // fuse & compound
    MockComptroller comptroller;
    MockFuseDirectory fuseDirectory;

    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 internal DELTA = 800672247590; // GROWTH_PER_SECOND + 1% = 25.25% APY

    uint8 public MODE = 0;
    address public ORACLE = address(123);
    uint256 public ISSUANCE_FEE = 0.1e18;
    uint256 public STAKE_SIZE = 1e18;
    uint256 public MIN_MATURITY = 2 weeks;
    uint256 public MAX_MATURITY = 14 weeks;
    uint256 public SPONSOR_WINDOW;
    uint256 public SETTLEMENT_WINDOW;

    struct Series {
        address zero; // Zero address for this Series (deployed on Series initialization)
        address claim; // Claim address for this Series (deployed on Series initialization)
        address sponsor; // Series initializer/sponsor
        uint256 issuance; // Issuance date for this Series (needed for Zero redemption)
        uint256 reward; // Tracks the fees due to the settler on Settlement
        uint256 iscale; // Scale value at issuance
        uint256 mscale; // Scale value at maturity
        uint256 stakeBal; // Balance staked at initialisation TODO: do we want to keep this?
        address stake; // Address of the stake stakeBal token TODO: do we want to keep this?
    }

    function setUp() public {
        hevm.warp(1630454400);
        // 01-09-21 00:00 UTC
        uint8 tDecimals = 18;
        stake = new MockToken("Stake Token", "ST", tDecimals);
        underlying = new MockToken("Dai Token", "DAI", tDecimals);
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", tDecimals);
        reward = new MockToken("Reward Token", "RT", tDecimals);
        GROWTH_PER_SECOND = convertToBase(GROWTH_PER_SECOND, target.decimals());
        DELTA = convertToBase(DELTA, target.decimals());

        // divider
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));
        divider.setGuard(address(target), 10 * 2**96);

        SPONSOR_WINDOW = divider.SPONSOR_WINDOW();
        SETTLEMENT_WINDOW = divider.SETTLEMENT_WINDOW();

        // balancer/space mocks
        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault));

        // fuse & comp mocks
        comptroller = new MockComptroller();
        fuseDirectory = new MockFuseDirectory(address(comptroller));
        masterOracle = new MockOracle();

        // pool manager
        poolManager = new PoolManager(
            address(fuseDirectory),
            address(comptroller),
            address(1),
            address(divider),
            address(1)
        );
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(masterOracle));
        PoolManager.AssetParams memory params = PoolManager.AssetParams({
            irModel: 0xEDE47399e2aA8f076d40DC52896331CBa8bd40f7,
            reserveFactor: 0.1 ether,
            collateralFactor: 0.5 ether,
            closeFactor: 0.051 ether,
            liquidationIncentive: 1 ether
        });
        poolManager.setParams("TARGET_PARAMS", params);

        // periphery
        periphery = new Periphery(
            address(divider),
            address(poolManager),
            address(spaceFactory),
            address(balancerVault)
        );
        divider.setPeriphery(address(periphery));
        poolManager.setIsTrusted(address(periphery), true);
        gClaimManager = new GClaimManager(address(divider));

        // adapter, target wrapper & factory
        factory = createFactory(address(target), address(reward));
        address f = periphery.onboardAdapter(address(factory), address(target)); // onboard target through Periphery
        adapter = MockAdapter(f);

        // users
        alice = createUser(2**96, 2**96);
        bob = createUser(2**96, 2**96);
        jim = createUser(2**96, 2**96);
    }

    function createUser(uint256 tBal, uint256 sBal) public returns (User user) {
        user = new User();
        user.setFactory(factory);
        user.setStake(stake);
        user.setTarget(target);
        user.setDivider(divider);
        user.setPeriphery(periphery);
        user.doApprove(address(underlying), address(periphery));
        user.doApprove(address(underlying), address(divider));
        user.doMint(address(underlying), tBal);
        user.doApprove(address(stake), address(periphery));
        user.doApprove(address(stake), address(divider));
        user.doMint(address(stake), sBal);
        user.doApprove(address(target), address(periphery));
        user.doApprove(address(target), address(divider));
        user.doApprove(address(target), address(user.gClaimManager()));
        user.doMint(address(target), tBal);
    }

    function createFactory(address _target, address _reward) public returns (MockFactory someFactory) {
        MockAdapter adapterImpl = new MockAdapter();
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            delta: DELTA,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE
        });
        someFactory = new MockFactory(address(adapterImpl), address(divider), factoryParams, address(_reward)); // deploy adapter factory
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);
    }

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint48 maturity) {
        maturity = uint48(DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0));
        require(maturity >= block.timestamp + 2 weeks, "Maturity must be 2 weeks from current timestamp");
    }

    function sponsorSampleSeries(address sponsor, uint48 maturity) public returns (address zero, address claim) {
        (zero, claim) = User(sponsor).doSponsorSeries(address(adapter), maturity);
    }

    function assertClose(uint256 actual, uint256 expected) public {
        if (actual == expected) return DSTest.assertEq(actual, expected);
        uint256 variance = 100;
        if (expected < variance) variance = 10;
        if (expected < variance) variance = 1;
        DSTest.assertTrue(actual >= (expected - variance));
        DSTest.assertTrue(actual <= (expected + variance));
    }

    function addLiquidityToBalancerVault(uint48 maturity, uint256 tBal) public {
        (address zero, address claim, , , , , , , ) = divider.series(address(adapter), maturity);
        uint256 issued = alice.doIssue(address(adapter), maturity, tBal);
        alice.doTransfer(claim, address(balancerVault), issued); // we don't really need this but we transfer them anyways
        alice.doTransfer(zero, address(balancerVault), issued);
        // we mint proportional underlying value. If proportion is 10%, we mint 10% more than what we've issued zeros.
        MockToken(adapter.getTarget()).mint(address(balancerVault), tBal);
    }

    function convertBase(uint256 decimals) public pure returns (uint256) {
        uint256 base = 1;
        base = decimals > 18 ? 10**(decimals - 18) : 10**(18 - decimals);
        return base;
    }

    function convertToBase(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals != 18) {
            amount = decimals > 18 ? amount * 10**(decimals - 18) : amount / 10**(18 - decimals);
        }
        return amount;
    }

    function calculateAmountToIssue(uint256 tBal, uint256 baseUnit) public returns (uint256 toIssue) {
        (, uint256 cscale) = adapter._lscale();
        //        uint256 cscale = divider.lscales(address(adapter), maturity, address(bob));
        toIssue = tBal.fmul(cscale, baseUnit);
    }

    function calculateExcess(
        uint256 tBal,
        uint48 maturity,
        address claim
    ) public returns (uint256 gap) {
        uint256 toIssue = calculateAmountToIssue(tBal, Token(claim).BASE_UNIT());
        gap = gClaimManager.excess(address(adapter), maturity, toIssue);
    }

    function fuzzWithBounds(
        uint96 number,
        uint96 lBound,
        uint96 uBound
    ) public returns (uint96) {
        return lBound + (number % (uBound - lBound));
    }

    function fuzzWithBounds(uint96 number, uint96 lBound) public returns (uint96) {
        return lBound + (number % (type(uint96).max - lBound));
    }
}
