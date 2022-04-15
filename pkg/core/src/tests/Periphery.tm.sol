// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { DSTest } from "./test-helpers/test.sol";
import { LiquidityHelper } from "./test-helpers/LiquidityHelper.sol";
import { Hevm } from "./test-helpers/Hevm.sol";

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Divider } from "../Divider.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";

// Mocks
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";
import { MockAdapter } from "./test-helpers/mocks/MockAdapter.sol";

// Constants/Addresses
import { Constants } from "./test-helpers/Constants.sol";
import { AddressBook } from "./test-helpers/AddressBook.sol";

import { BalancerVault } from "../external/balancer/Vault.sol";
import { BalancerPool } from "../external/balancer/Pool.sol";

interface SpaceFactoryLike {
    function create(address, uint256) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);

    function setParams(
        uint256 _ts,
        uint256 _g1,
        uint256 _g2,
        bool _oracleEnabled
    ) external;
}

contract PeripheryTestHelper is DSTest, LiquidityHelper {
    Periphery internal periphery;

    MockAdapter internal mockAdapter;
    MockOracle internal mockOracle;
    MockTarget internal mockTarget;

    address internal balancerVault;
    address internal spaceFactory;
    address internal poolManager;
    address internal divider;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 firstDayOfMonth = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        hevm.warp(firstDayOfMonth); // Set to first day of the month

        MockToken underlying = new MockToken("TestUnderlying", "TU", 18);
        mockTarget = new MockTarget(address(underlying), "TestTarget", "TT", 18);

        // Mainnet contracts
        divider = AddressBook.DIVIDER_1_2_0;
        spaceFactory = AddressBook.SPACE_FACTORY_1_2_0;
        balancerVault = AddressBook.BALANCER_VAULT;
        poolManager = AddressBook.POOL_MANAGER_1_2_0;

        mockOracle = new MockOracle();
        mockAdapter = new MockAdapter(
            address(divider),
            address(mockTarget),
            address(mockOracle),
            0, // no issuance fees
            address(new MockToken("Stake", "ST", 18)), // stake size is 0, so the we don't actually need any stake token
            0,
            0, // 0 minm, so there's not lower bound on future maturity
            type(uint64).max, // large maxm, so there's not upper bound on future maturity
            0, // monthly maturities
            0,
            Constants.DEFAULT_LEVEL,
            address(new MockToken("Reward", "R", 18))
        );

        hevm.label(AddressBook.SPACE_FACTORY_1_2_0, "SpaceFactory");

        periphery = new Periphery(divider, poolManager, spaceFactory, balancerVault);

        // Start multisig (admin) prank calls
        hevm.startPrank(AddressBook.SENSE_ADMIN_MULTISIG);
        Divider(divider).setPeriphery(address(periphery));
        Divider(divider).setGuard(address(mockAdapter), type(uint256).max);
        PoolManager(poolManager).setIsTrusted(address(periphery), true);
        uint256 ts = 1e18 / (uint256(31536000) * uint256(12));
        uint256 g1 = (uint256(950) * 1e18) / uint256(1000);
        uint256 g2 = (uint256(1000) * 1e18) / uint256(950);
        SpaceFactoryLike(spaceFactory).setParams(ts, g1, g2, true);
        hevm.stopPrank(); // Stop prank calling

        periphery.onboardAdapter(address(mockAdapter), true);
        periphery.verifyAdapter(address(mockAdapter), true);

        // Set adapter scale to 1
        mockAdapter.setScale(1e18);

        // Give the Periphery approvals for the mock Target
        mockTarget.approve(address(periphery), type(uint256).max);
    }
}

contract PeripheryMainnetTests is PeripheryTestHelper {
    using FixedMath for uint256;

    function testMainnetSponsorSeries() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // Check PT and YT contracts deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded via the PoolManager into Fuse
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(mockAdapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSwapYTsForTarget() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 0.5 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 10% of this address' YTs for Target
        uint256 ytBalPre = ERC20(yt).balanceOf(address(this));
        uint256 targetBalPre = mockTarget.balanceOf(address(this));
        ERC20(yt).approve(address(periphery), ytBalPre / 10);
        periphery.swapYTsForTarget(address(mockAdapter), maturity, ytBalPre / 10);
        uint256 ytBalPost = ERC20(yt).balanceOf(address(this));
        uint256 targetBalPost = mockTarget.balanceOf(address(this));

        // Check that this address has fewer YTs and more Target
        assertGt(ytBalPre, ytBalPost);
        assertLt(targetBalPre, targetBalPost);
    }

    function testMainnetSwapTargetForYTsReturnValues() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 0.005 of this address' Target for YTs
        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.048367e18; // Calculated using sense-v1/yt-buying-lib

        uint256 targetBalPre = mockTarget.balanceOf(address(this));
        uint256 ytBalPre = ERC20(yt).balanceOf(address(this));
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW // Min out is just the amount of Target borrowed
            // (if at least the Target borrowed is not swapped out, then we won't be able to pay back the flashloan)
        );
        uint256 targetBalPost = mockTarget.balanceOf(address(this));
        uint256 ytBalPost = ERC20(yt).balanceOf(address(this));

        // Check that the return values reflect the token balance changes
        assertEq(targetBalPre - targetBalPost + targetReturned, TARGET_IN);
        assertEq(ytBalPost - ytBalPre, ytsOut);
        // Check that the YTs returned are the result of issuing from the borrowed Target + transferred Target
        assertEq(ytsOut, TARGET_IN + TARGET_TO_BORROW);

        // Check that we got less than 0.000001 Target back
        assertTrue(targetReturned < 0.000001e18);
    }

    // Pattern similar to https://github.com/FrankieIsLost/gradual-dutch-auction/src/test/ContinuousGDA.t.sol#L113
    function testMainnetSwapTargetForYTsBorrowCheckOne() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.048367e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckTwo() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.01e18;
        uint256 TARGET_TO_BORROW = 0.0914916e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckThree() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1887859e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckFour() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.00003e18;
        uint256 TARGET_TO_BORROW = 0.000308950023870e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowTooMuch() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);
        
        uint256 TARGET_IN = 0.0234e18;
        // Check that borrowing too much Target will make it so that we can't pay back the flashloan
        uint256 TARGET_TO_BORROW = 0.1887859e18 + 0.1e18;
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsMinOut() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.048367e18;

        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW out from swapping TARGET_TO_BORROW / 2 + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW / 2, TARGET_TO_BORROW); // external call to catch the revert

        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW * 1.01 out from swapping TARGET_TO_BORROW + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW * 1.01e18 / 1e18);

        // Get the Target amount we'll get back once we buy YTs with these set params, then revert any state changes
        uint256 targetReturned;
        try this._callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW) {}
        catch Error(string memory retData) {
            (targetReturned, ) = abi.decode(bytes(retData), (uint256, uint256));
        }
        // Sanity check
        assertGt(targetReturned, 0);

        // Check that setting the min out as one more than the target we know we'll get fails
        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW + targetReturned + 1);

        // Check that setting the min out to exactly the target we know we'll get succeeds
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW + targetReturned);
    }

    function testMainnetFuzzSwapTargetForYTsDifferentDecimals(uint8 underlyingDecimals, uint8 targetDecimals) public {
        // Bound decimals to be between 4 and 18, inclusive
        underlyingDecimals = _fuzzWithBounds(underlyingDecimals, 4, 19);
        targetDecimals = _fuzzWithBounds(targetDecimals, 4, 19);
        MockToken newUnderlying = new MockToken("TestUnderlying", "TU", underlyingDecimals);
        MockTarget newMockTarget = new MockTarget(address(newUnderlying), "TestTarget", "TT", targetDecimals);

        // 1. Swap out the Target/Underlying tokens for new ones with different decimals vaules
        hevm.etch(mockTarget.underlying(), address(newUnderlying).code);
        hevm.etch(address(mockTarget), address(newMockTarget).code);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();
        // Sanity check that the new PT/YT tokens are using the updated decimals
        assertEq(uint256(ERC20(pt).decimals()), uint256(targetDecimals));

        // 3. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 10**targetDecimals, 10**targetDecimals / 2);

        // Check buying YT params calculated using sense-v1/yt-buying-lib, adjusted for the target's decimals
        uint256 TARGET_IN = 0.0234e18 * 10**targetDecimals / 1e18;
        uint256 TARGET_TO_BORROW = 0.1887859e18 * 10**targetDecimals / 1e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    // INTERNAL HELPERS ––––––––––––

    function _sponsorSeries()
        public
        returns (
            uint256 maturity,
            address pt,
            address yt
        )
    {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        maturity = DateTimeFull.timestampFromDateTime(year + 1, month, 1, 0, 0, 0);
        (pt, yt) = periphery.sponsorSeries(address(mockAdapter), maturity, false);
    }

    function _initializePool(uint256 maturity, ERC20 pt, uint256 targetToJoin, uint256 ptsToSwapIn) public {
        // Issue some PTs & YTs
        mockTarget.mint(address(this), targetToJoin + ptsToSwapIn);
        mockTarget.approve(address(divider), ptsToSwapIn);
        Divider(divider).issue(address(mockAdapter), maturity, ptsToSwapIn);
        // Sanity check that scale is 1 and there is no issuance fee. ie PTs are issued 1:1 for Target
        assertEq(pt.balanceOf(address(this)), ptsToSwapIn);

        // Add Target to the Space pool
        periphery.addLiquidityFromTarget(address(mockAdapter), maturity, targetToJoin, 1, 0);

        // 5. Swap PT balance in for Target to initialize the PT side of the pool
        pt.approve(address(periphery), ptsToSwapIn);
        periphery.swapPTsForTarget(address(mockAdapter), maturity, ptsToSwapIn, 0);
    }

    function _checkYTBuyingParameters(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut
        );

        // Check that we got less than 0.01% of our Target back
        require(targetReturned <= targetIn * 0.0001e18 / 1e18, "TOO_MANY_TARGET_RETURNED");

        // Check that the YTs returned are the result of issuing from the borrowed Target + transferred Target
        assertEq(ytsOut, targetIn + targetToBorrow);
    }

    function _callStaticBuyYTs(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut
        );

        revert(string(abi.encode(targetReturned, ytsOut)));
    }

    // Fuzz with bounds, inclusive of the lower bound, not inclusive of the upper bound
    function _fuzzWithBounds(
        uint8 number,
        uint8 lBound,
        uint8 uBound
    ) public returns (uint8) {
        return lBound + (number % (uBound - lBound));
    }
}
