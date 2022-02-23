// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

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
import { MockSpaceFactory, MockBalancerVault } from "./mocks/MockSpace.sol";

// Fuse & compound mocks
import { MockComptroller } from "./mocks/fuse/MockComptroller.sol";
import { MockFuseDirectory } from "./mocks/fuse/MockFuseDirectory.sol";
import { MockOracle } from "./mocks/fuse/MockOracle.sol";

import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { DSTest } from "./DSTest.sol";
import { Hevm } from "./Hevm.sol";
import { DateTimeFull } from "./DateTimeFull.sol";
import { User } from "./User.sol";
import { FixedMath } from "../../external/FixedMath.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

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

    uint16 public MODE = 0;
    address public ORACLE = address(123);
    uint64 public ISSUANCE_FEE = 0.1e18;
    uint256 public STAKE_SIZE = 1e18;
    uint256 public MIN_MATURITY = 2 weeks;
    uint256 public MAX_MATURITY = 14 weeks;
    uint16 public DEFAULT_LEVEL = 31;
    uint256 public SPONSOR_WINDOW;
    uint256 public SETTLEMENT_WINDOW;

    function setUp() public virtual {
        hevm.warp(1630454400);
        // 01-09-21 00:00 UTC
        uint8 baseDecimals = 18;
        stake = new MockToken("Stake Token", "ST", baseDecimals);
        underlying = new MockToken("Dai Token", "DAI", baseDecimals);
        // Get Target decimal number from the environment
        string[] memory inputs = new string[](2);
        inputs[0] = "just";
        inputs[1] = "_forge_mock_target_decimals";
        uint8 targetDecimals = uint8(abi.decode(hevm.ffi(inputs), (uint256)));
        target = new MockTarget(address(underlying), "Compound Dai", "cDAI", targetDecimals);
        emit log_named_uint(
            "Running tests with the Mock Target configured with the following number of decimals",
            uint256(targetDecimals)
        );

        reward = new MockToken("Reward Token", "RT", baseDecimals);
        GROWTH_PER_SECOND = convertToBase(GROWTH_PER_SECOND, target.decimals());

        // divider
        tokenHandler = new TokenHandler();
        divider = new Divider(address(this), address(tokenHandler));
        tokenHandler.init(address(divider));

        SPONSOR_WINDOW = divider.SPONSOR_WINDOW();
        SETTLEMENT_WINDOW = divider.SETTLEMENT_WINDOW();

        // balancer/space mocks
        balancerVault = new MockBalancerVault();
        spaceFactory = new MockSpaceFactory(address(balancerVault), address(divider));

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
            address(masterOracle) // oracle impl
        );
        poolManager.deployPool("Sense Fuse Pool", 0.051 ether, 1 ether, address(1));
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
        address f = periphery.deployAdapter(address(factory), address(target)); // deploy & onboard target through Periphery
        adapter = MockAdapter(f);
        divider.setGuard(address(adapter), 10 * 2**128);

        // users
        alice = createUser(2**128, 2**128);
        bob = createUser(2**128, 2**128);
        jim = createUser(2**128, 2**128);
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
        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: address(stake),
            oracle: ORACLE,
            ifee: ISSUANCE_FEE,
            stakeSize: STAKE_SIZE,
            minm: MIN_MATURITY,
            maxm: MAX_MATURITY,
            mode: MODE,
            tilt: 0
        });
        someFactory = new MockFactory(address(divider), factoryParams, address(_reward)); // deploy adapter factory
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
        periphery.setFactory(address(someFactory), true);
    }

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint256 maturity) {
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        if (maturity < block.timestamp + 2 weeks) revert Errors.InvalidMaturityOffsets();
    }

    function sponsorSampleSeries(address sponsor, uint256 maturity) public returns (address zero, address claim) {
        (zero, claim) = User(sponsor).doSponsorSeries(address(adapter), maturity);
    }

    function assertClose(
        uint256 a,
        uint256 b,
        uint256 _tolerance
    ) public {
        uint256 diff = a < b ? b - a : a - b;
        if (diff > _tolerance) {
            emit log("Error: abs(a, b) < tolerance not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("  Tolerance", _tolerance);
            emit log_named_uint("    Actual", a);
            fail();
        }
    }

    function assertClose(uint256 a, uint256 b) public {
        uint256 variance = 100;
        if (b < variance) variance = 10;
        if (b < variance) variance = 1;
        assertClose(a, b, variance);
    }

    function addLiquidityToBalancerVault(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) public {
        return _addLiquidityToBalancerVault(adapter, maturity, tBal);
    }

    function addLiquidityToBalancerVault(uint256 maturity, uint256 tBal) public {
        return _addLiquidityToBalancerVault(address(adapter), maturity, tBal);
    }

    function _addLiquidityToBalancerVault(
        address adapter,
        uint256 maturity,
        uint256 tBal
    ) internal {
        uint256 issued = alice.doIssue(adapter, maturity, tBal);
        alice.doTransfer(divider.claim(address(adapter), maturity), address(balancerVault), issued); // we don't really need this but we transfer them anyways
        alice.doTransfer(divider.zero(address(adapter), maturity), address(balancerVault), issued);
        // we mint proportional underlying value. If proportion is 10%, we mint 10% more than what we've issued zeros.
        MockToken(MockAdapter(adapter).target()).mint(address(balancerVault), tBal);
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

    function calculateAmountToIssue(uint256 tBal) public returns (uint256 toIssue) {
        (, uint256 cscale) = adapter.lscale();
        //        uint256 cscale = divider.lscales(address(adapter), maturity, address(bob));
        toIssue = tBal.fmul(cscale, FixedMath.WAD);
    }

    function calculateExcess(
        uint256 tBal,
        uint256 maturity,
        address claim
    ) public returns (uint256 gap) {
        uint256 toIssue = calculateAmountToIssue(tBal);
        gap = gClaimManager.excess(address(adapter), maturity, toIssue);
    }

    function fuzzWithBounds(
        uint128 number,
        uint128 lBound,
        uint128 uBound
    ) public returns (uint128) {
        return lBound + (number % (uBound - lBound));
    }

    function fuzzWithBounds(uint128 number, uint128 lBound) public returns (uint128) {
        return lBound + (number % (type(uint128).max - lBound));
    }

    function getError(uint256 errCode) internal pure returns (string memory errString) {
        return string(bytes.concat(bytes("SNS#"), bytes(Strings.toString(errCode))));
    }

    function toUint256(bytes memory _bytes) internal pure returns (uint256 value) {
        assembly {
            value := mload(add(_bytes, 0x20))
        }
    }
}
