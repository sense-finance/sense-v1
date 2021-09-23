// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "ds-test/test.sol";

// internal references
import "../Hevm.sol";
import "../MockToken.sol";
import "../feed/MockFeed.sol";
import "./User.sol";
import "../../../Divider.sol";
import "../DateTimeFull.sol";

contract DividerTest is DSTest {
    MockFeed feed;
    MockToken stable;
    MockToken target;

    Divider internal divider;
    User internal gov;
    User internal alice;
    User internal bob;
    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    uint256 public constant ISSUANCE_FEE = 1; // In percentage (1%). Hardcoded value at least for v1.
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
        stable = new MockToken("Stable Token", "ST");
        target = new MockToken("Compound Dai", "cDAI");

        gov = new User();
        gov.setStable(stable);
        gov.setTarget(target);
        divider = new Divider(address(stable), address(gov));
        gov.setDivider(divider);

        feed = new MockFeed(address(target), address(divider), 150, 150);
        divider.setFeed(address(feed), true);

        alice = createUser();
        bob = createUser();
    }

    function createUser() public returns (User user) {
        user = new User();
        user.setStable(stable);
        user.setTarget(target);
        user.setDivider(divider);
        user.doApprove(address(stable), address(divider));
        user.doMint(address(stable), INIT_STAKE * 1000);
        user.doApprove(address(target), address(divider));
        user.doMint(address(target), INIT_STAKE * 10000);
    }

    /* ========== test helpers ========== */

    function getValidMaturity(uint256 year, uint256 month) public view returns (uint256 maturity) {
        maturity = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        require(maturity >= block.timestamp + 2 weeks, "Can not return valid maturity with given year an month");
    }

    function initSampleSeries(address sponsor, uint256 maturity) public returns (address zero, address claim) {
        (zero, claim) = User(sponsor).doInitSeries(address(feed), maturity);
    }

    function assertClose(uint256 actual, uint256 expected) public {
        uint256 variance = 10;
        assertTrue(actual >= (expected - variance));
        assertTrue(actual <= (expected + variance));
    }
}
