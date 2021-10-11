// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { DSTest } from "ds-test/test.sol";

// Internal references
import { GClaim } from "../../modules/GClaim.sol";
import { Divider } from "../../Divider.sol";
import { MockToken } from "./MockToken.sol";
import { MockFeed } from "./MockFeed.sol";
import { MockFactory } from "./MockFactory.sol";

import { Hevm } from "./Hevm.sol";
import { DateTimeFull } from "./DateTimeFull.sol";
import { User } from "./User.sol";

contract TestHelper is DSTest {
    MockFeed feed;
    MockToken stable;
    MockToken target;
    MockFactory factory;

    Divider internal divider;
    GClaim internal gclaim;
    User internal alice;
    User internal bob;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 internal DELTA = 800672247590; // GROWTH_PER_SECOND + 1% = 25.25% APY

    uint256 public constant ISSUANCE_FEE = 0.01e18; // In percentage (1%). Hardcoded value at least for v1.
    uint256 public constant INIT_STAKE = 1e18; // Hardcoded value at least for v1.
    uint public constant SPONSOR_WINDOW = 4 hours; // Hardcoded value at least for v1.
    uint public constant SETTLEMENT_WINDOW = 2 hours; // Hardcoded value at least for v1.
    uint public constant MIN_MATURITY = 2 weeks; // Hardcoded value at least for v1.
    uint public constant MAX_MATURITY = 14 weeks; // Hardcoded value at least for v1.

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
        uint256 tBase = 10 ** tDecimals;
        uint256 convertBase = 1;
        if (tDecimals != 18) {
            convertBase = tDecimals > 18 ? 10 ** (tDecimals - 18) : 10 ** (18 - tDecimals);
        }
        target = new MockToken("Compound Dai", "cDAI", tDecimals);
        GROWTH_PER_SECOND = GROWTH_PER_SECOND / convertBase;
        DELTA = DELTA / convertBase;

        // divider
        divider = new Divider(address(stable), address(this));
        divider.setGuard(address(target), 2**96);

        // feed & factory
        MockFeed implementation = new MockFeed(); // feed implementation
        factory = new MockFactory(address(implementation), address(divider), DELTA); // deploy feed factory
        factory.addTarget(address(target), true); // add support to target
        divider.setIsTrusted(address(factory), true); // add factory as a ward
        feed = MockFeed(factory.deployFeed(address(target)));

        // modules
        gclaim = new GClaim(address(divider));

        // users
        alice = createUser(2**96, 2**96);
        bob = createUser(2**96, 2**96);
    }

    function createUser(uint256 tBal, uint256 sBal) public returns (User user) {
        user = new User();
        user.setFactory(factory);
        user.setStable(stable);
        user.setTarget(target);
        user.setDivider(divider);
        user.setGclaim(gclaim);
        user.doApprove(address(stable), address(divider));
        uint256 sBase = 10 ** stable.decimals();
        user.doMint(address(stable), sBal);
        user.doApprove(address(target), address(divider));
        uint256 tBase = 10 ** target.decimals();
        user.doMint(address(target), tBal);
    }

    function createFactory(address _target) public returns (MockFactory someFactory) {
        MockFeed implementation = new MockFeed();
        someFactory = new MockFactory(address(implementation), address(divider), DELTA);
        someFactory.addTarget(_target, true);
        divider.setIsTrusted(address(someFactory), true);
    }

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint256 maturity) {
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        require(maturity >= block.timestamp + 2 weeks, "Maturity must be 2 weeks from current timestamp");
    }

    function initSampleSeries(address sponsor, uint256 maturity) public returns (address zero, address claim) {
        (zero, claim) = User(sponsor).doInitSeries(address(feed), maturity);
    }

    function assertClose(uint256 actual, uint256 expected) public {
        if (actual == expected) return DSTest.assertEq(actual, expected);
        uint256 variance = 100;
        if (expected < variance) variance = 10;
        if (expected < variance) variance = 1;
        DSTest.assertTrue(actual >= (expected - variance));
        DSTest.assertTrue(actual <= (expected + variance));
    }

}
