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
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { CAdapter } from "../adapters/implementations/compound/CAdapter.sol";
import { FAdapter } from "../adapters/implementations/fuse/FAdapter.sol";
import { CFactory } from "../adapters/implementations/compound/CFactory.sol";
import { FFactory } from "../adapters/implementations/fuse/FFactory.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";

// Mocks
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockAdapter, MockCropAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";

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
    uint256 public origin;

    Periphery internal periphery;

    CFactory internal cfactory;
    FFactory internal ffactory;

    MockOracle internal mockOracle;
    MockTarget internal mockTarget;
    MockCropAdapter internal mockAdapter;

    // Mainnet contracts for forking
    address internal balancerVault;
    address internal spaceFactory;
    address internal poolManager;
    address internal divider;

    Hevm internal constant hevm = Hevm(HEVM_ADDRESS);

    // Fee used for testing YT swaps, must be accounted for when doing external ref checks with the yt buying lib
    uint128 internal constant IFEE_FOR_YT_SWAPS = 0.042e18; // 4.2%

    function setUp() public {
        origin = block.timestamp;
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
        BaseAdapter.AdapterParams memory mockAdapterParams = BaseAdapter.AdapterParams({
            oracle: address(mockOracle),
            stake: address(new MockToken("Stake", "ST", 18)), // stake size is 0, so the we don't actually need any stake token
            stakeSize: 0,
            minm: 0, // 0 minm, so there's not lower bound on future maturity
            maxm: type(uint64).max, // large maxm, so there's not upper bound on future maturity
            mode: 0, // monthly maturities
            tilt: 0,
            level: Constants.DEFAULT_LEVEL
        });
        mockAdapter = new MockCropAdapter(
            address(divider),
            address(mockTarget),
            mockTarget.underlying(),
            IFEE_FOR_YT_SWAPS,
            mockAdapterParams,
            address(new MockToken("Reward", "R", 18))
        );

        hevm.label(spaceFactory, "SpaceFactory");

        BaseFactory.FactoryParams memory factoryParams = BaseFactory.FactoryParams({
            stake: AddressBook.DAI,
            oracle: address(mockOracle),
            ifee: Constants.DEFAULT_ISSUANCE_FEE,
            stakeSize: Constants.DEFAULT_STAKE_SIZE,
            minm: Constants.DEFAULT_MIN_MATURITY,
            maxm: Constants.DEFAULT_MAX_MATURITY,
            mode: Constants.DEFAULT_MODE,
            tilt: Constants.DEFAULT_TILT,
            guard: Constants.DEFAULT_GUARD
        });

        cfactory = new CFactory(divider, factoryParams, AddressBook.COMP);
        ffactory = new FFactory(divider, factoryParams);

        periphery = new Periphery(divider, poolManager, spaceFactory, balancerVault);

        periphery.setFactory(address(cfactory), true);
        periphery.setFactory(address(ffactory), true);

        // Start multisig (admin) prank calls
        hevm.startPrank(AddressBook.SENSE_ADMIN_MULTISIG);

        // Give authority to factories soy they can setGuard when deploying adapters
        Divider(divider).setIsTrusted(address(cfactory), true);
        Divider(divider).setIsTrusted(address(ffactory), true);

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

    /* ========== SERIES SPONSORING ========== */

    function testMainnetSponsorSeriesOnCAdapter() public {
        // We roll back to original block number (which is the latest block) because the call chainlink's oracle
        // somehow is not being done taking into consideration the warped block (maybe a bug in foundry?)
        hevm.warp(origin);
        address f = periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "");
        CAdapter cadapter = CAdapter(payable(f));
        // Mint this address MAX_UINT AddressBook.DAI
        giveTokens(AddressBook.DAI, type(uint256).max, hevm);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        ERC20(AddressBook.DAI).approve(address(periphery), type(uint256).max);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesOnFAdapter() public {
        // We roll back to original block number (which is the latest block) because the call chainlink's oracle
        // somehow is not being done taking into consideration the warped block (maybe a bug in foundry?)
        hevm.warp(origin);
        address f = periphery.deployAdapter(
            address(ffactory),
            AddressBook.f156FRAX3CRV,
            abi.encode(AddressBook.TRIBE_CONVEX)
        );
        FAdapter fadapter = FAdapter(payable(f));
        // Mint this address MAX_UINT AddressBook.DAI for stake
        giveTokens(AddressBook.DAI, type(uint256).max, hevm);

        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(
            block.timestamp + Constants.DEFAULT_MIN_MATURITY
        );
        uint256 maturity = DateTimeFull.timestampFromDateTime(
            month == 12 ? year + 1 : year,
            month == 12 ? 1 : (month + 1),
            1,
            0,
            0,
            0
        );

        ERC20(AddressBook.DAI).approve(address(periphery), type(uint256).max);
        (address pt, address yt) = periphery.sponsorSeries(address(fadapter), maturity, false);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(fadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesOnMockAdapter() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // Check that the PT and YT contracts have been deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check that PTs and YTs are onboarded via the PoolManager into Fuse
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(mockAdapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    /* ========== YT SWAPS ========== */

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
        assertLt(ytBalPost, ytBalPre);
        assertGt(targetBalPost, targetBalPre);
    }

    function testMainnetSwapTargetForYTsReturnValues() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 0.005 of this address' Target for YTs
        uint256 TARGET_IN = 0.0234e18;
        // Calculated using sense-v1/yt-buying-lib
        uint256 TARGET_TO_BORROW = 0.1413769e18;

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
        assertEq(ytsOut, (TARGET_IN + TARGET_TO_BORROW).fmul(1e18 - mockAdapter.ifee()));

        // Check that we got less than 0.000001 Target back
        assertTrue(targetReturned < 0.000001e18);
    }

    // Pattern similar to https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/test/ContinuousGDA.t.sol#L113
    function testMainnetSwapTargetForYTsBorrowCheckOne() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.03340541e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckTwo() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.01e18;
        uint256 TARGET_TO_BORROW = 0.06489898e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckThree() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckFour() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.00003e18;
        uint256 TARGET_TO_BORROW = 0.0002066353449e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowTooMuch() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        // Check that borrowing too much Target will make it so that we can't pay back the flashloan
        uint256 TARGET_TO_BORROW = 0.1413769e18 + 0.02e18;
        hevm.expectRevert("TRANSFER_FROM_FAILED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsBorrowTooLittle() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        // Check that borrowing too few Target will cause us to get too many Target back
        uint256 TARGET_TO_BORROW = 0.1413769e18 - 0.02e18;
        hevm.expectRevert("TOO_MANY_TARGET_RETURNED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsMinOut() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;

        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW out from swapping TARGET_TO_BORROW / 2 + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW / 2, TARGET_TO_BORROW); // external call to catch the revert

        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW * 1.01 out from swapping TARGET_TO_BORROW + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW.fmul(1.01e18));

        // 3. Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        // Sanity check
        assertGt(targetReturnedPreview, 0);

        // Check that setting the min out to one more than the target we previewed fails
        hevm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        this._checkYTBuyingParameters(
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW + targetReturnedPreview + 1
        );

        // Check that setting the min out to exactly the target we previewed succeeds
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW + targetReturnedPreview);
    }

    function testMainnetSwapTargetForYTsTransferOutOfBounds() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        uint256 TARGET_TRANSFERRED_IN = 0.5e18;

        // Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        mockTarget.mint(address(periphery), TARGET_TRANSFERRED_IN);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW
        );

        assertEq(targetReturnedPreview + TARGET_TRANSFERRED_IN, targetReturned);
        assertEq(ytsOut, (TARGET_IN + TARGET_TO_BORROW).fmul(1e18 - mockAdapter.ifee()));
    }

    function testMainnetFuzzSwapTargetForYTsDifferentDecimals(uint8 underlyingDecimals, uint8 targetDecimals) public {
        // Bound decimals to between 4 and 18, inclusive
        underlyingDecimals = _fuzzWithBounds(underlyingDecimals, 4, 19);
        targetDecimals = _fuzzWithBounds(targetDecimals, 4, 19);
        MockToken newUnderlying = new MockToken("TestUnderlying", "TU", underlyingDecimals);
        MockTarget newMockTarget = new MockTarget(address(newUnderlying), "TestTarget", "TT", targetDecimals);

        // 1. Switch the Target/Underlying tokens out for new ones with different decimals vaules
        hevm.etch(mockTarget.underlying(), address(newUnderlying).code);
        hevm.etch(address(mockTarget), address(newMockTarget).code);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();
        // Sanity check that the new PT/YT tokens are using the updated decimals
        assertEq(uint256(ERC20(pt).decimals()), uint256(targetDecimals));

        // 3. Initialize the pool by joining 1 base unit of Target in, then swapping 0.5 base unit PTs in for Target
        _initializePool(maturity, ERC20(pt), 10**targetDecimals, 10**targetDecimals / 2);

        // Check buying YT params calculated using sense-v1/yt-buying-lib, adjusted for the target's decimals
        uint256 TARGET_IN = uint256(0.0234e18).fmul(10**targetDecimals);
        uint256 TARGET_TO_BORROW = uint256(0.1413769e18).fmul(10**targetDecimals);
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetFuzzSwapTargetForYTsDifferentScales(uint64 initScale, uint64 scale) public {
        hevm.assume(initScale >= 1e9);
        hevm.assume(scale >= initScale);

        // 1. Initialize scale
        mockAdapter.setScale(initScale);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 3. Initialize the pool by joining 1 Underlying worth of Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), uint256(1e18).fdivUp(initScale), 0.5e18);

        // 4. Update scale
        mockAdapter.setScale(scale);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib, adjusted with the current scale
        uint256 TARGET_IN = uint256(0.0234e18).fdivUp(scale);
        uint256 TARGET_TO_BORROW = uint256(0.1413769e18).fdivUp(scale);
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
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

    function _initializePool(
        uint256 maturity,
        ERC20 pt,
        uint256 targetToJoin,
        uint256 ptsToSwapIn
    ) public {
        // Issue some PTs (& YTs) we'll use to initialize the pool with
        uint256 targetToIssueWith = ptsToSwapIn.fdivUp(1e18 - mockAdapter.ifee()).fdivUp(mockAdapter.scale());
        mockTarget.mint(address(this), targetToIssueWith + targetToJoin);
        mockTarget.approve(address(divider), targetToIssueWith);
        Divider(divider).issue(address(mockAdapter), maturity, targetToIssueWith);
        // Sanity check that we have the PTs we need to swap in, either exactly, or close to (modulo rounding)
        assertTrue(pt.balanceOf(address(this)) >= ptsToSwapIn && pt.balanceOf(address(this)) <= ptsToSwapIn + 100);

        // Add Target to the Space pool
        periphery.addLiquidityFromTarget(address(mockAdapter), maturity, targetToJoin, 1, 0);

        // Swap PT balance in for Target to initialize the PT side of the pool
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

        // Check that less than 0.01% of our Target got returned
        require(targetReturned <= targetIn.fmul(0.0001e18), "TOO_MANY_TARGET_RETURNED");
    }

    function _callStaticBuyYTs(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public returns (uint256 targetReturnedPreview, uint256 ytsOutPreview) {
        try this._callRevertBuyYTs(maturity, targetIn, targetToBorrow, minOut) {} catch Error(string memory retData) {
            (targetReturnedPreview, ytsOutPreview) = abi.decode(bytes(retData), (uint256, uint256));
        }
    }

    function _callRevertBuyYTs(
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
