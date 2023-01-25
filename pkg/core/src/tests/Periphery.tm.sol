// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/PoolManager.sol";
import { Divider } from "../Divider.sol";
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { CAdapter } from "../adapters/implementations/compound/CAdapter.sol";
import { FAdapter } from "../adapters/implementations/fuse/FAdapter.sol";
import { CFactory } from "../adapters/implementations/compound/CFactory.sol";
import { FFactory } from "../adapters/implementations/fuse/FFactory.sol";

import { DateTimeFull } from "./test-helpers/DateTimeFull.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

// Mocks
import { MockOracle } from "./test-helpers/mocks/fuse/MockOracle.sol";
import { MockAdapter, MockCropAdapter } from "./test-helpers/mocks/MockAdapter.sol";
import { MockTarget } from "./test-helpers/mocks/MockTarget.sol";
import { MockToken } from "./test-helpers/mocks/MockToken.sol";

// Permit2
import { Permit2Helper } from "./test-helpers/Permit2Helper.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

// Constants/Addresses
import { Constants } from "./test-helpers/Constants.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";

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

contract PeripheryTestHelper is ForkTest, Permit2Helper {
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
    address internal stake;

    uint256 internal bobPrivKey = _randomUint256();
    address internal bob = vm.addr(bobPrivKey);

    // Fee used for testing YT swaps, must be accounted for when doing external ref checks with the yt buying lib
    uint128 internal constant IFEE_FOR_YT_SWAPS = 0.042e18; // 4.2%

    function setUp() public {
        fork();
        origin = block.timestamp;
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 firstDayOfMonth = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        vm.warp(firstDayOfMonth); // Set to first day of the month

        MockToken underlying = new MockToken("TestUnderlying", "TU", 18);
        mockTarget = new MockTarget(address(underlying), "TestTarget", "TT", 18);

        // Mainnet contracts
        divider = AddressBook.DIVIDER_1_2_0;
        spaceFactory = AddressBook.SPACE_FACTORY_1_2_0;
        balancerVault = AddressBook.BALANCER_VAULT;
        poolManager = AddressBook.POOL_MANAGER_1_2_0;
        stake = address(new MockToken("Stake", "ST", 18));

        mockOracle = new MockOracle();
        BaseAdapter.AdapterParams memory mockAdapterParams = BaseAdapter.AdapterParams({
            oracle: address(mockOracle),
            stake: stake, // stake size is 0, so the we don't actually need any stake token
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
            Constants.REWARDS_RECIPIENT,
            IFEE_FOR_YT_SWAPS,
            mockAdapterParams,
            address(new MockToken("Reward", "R", 18))
        );

        vm.label(spaceFactory, "SpaceFactory");

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

        cfactory = new CFactory(
            divider,
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT,
            factoryParams,
            AddressBook.COMP
        );
        ffactory = new FFactory(divider, Constants.RESTRICTED_ADMIN, Constants.REWARDS_RECIPIENT, factoryParams);

        permit2 = IPermit2(AddressBook.PERMIT2);
        periphery = new Periphery(divider, poolManager, spaceFactory, balancerVault, address(permit2));

        periphery.setFactory(address(cfactory), true);
        periphery.setFactory(address(ffactory), true);

        // Start multisig (admin) prank calls
        vm.startPrank(AddressBook.SENSE_MULTISIG);

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

        vm.stopPrank(); // Stop prank calling

        periphery.onboardAdapter(address(mockAdapter), true);
        periphery.verifyAdapter(address(mockAdapter), true);

        // Set adapter scale to 1
        mockAdapter.setScale(1e18);

        // Give the permit2 approvals for the mock Target
        vm.prank(bob);
        mockTarget.approve(AddressBook.PERMIT2, type(uint256).max);
    }
}

contract PeripheryMainnetTests is PeripheryTestHelper {
    using FixedMath for uint256;

    /* ========== SERIES SPONSORING ========== */

    function testMainnetSponsorSeriesOnCAdapter() public {
        // We roll back to original block number (which is the latest block) because the call chainlink's oracle
        // somehow is not being done taking into consideration the warped block (maybe a bug in foundry?)
        vm.warp(origin);
        address f = periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "");
        CAdapter cadapter = CAdapter(payable(f));
        // Mint bob MAX_UINT AddressBook.DAI
        deal(AddressBook.DAI, bob, type(uint256).max);
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

        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(AddressBook.PERMIT2, type(uint256).max);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.DAI);
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data);

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
        vm.warp(origin);
        address f = periphery.deployAdapter(
            address(ffactory),
            AddressBook.f156FRAX3CRV,
            abi.encode(AddressBook.TRIBE_CONVEX)
        );
        FAdapter fadapter = FAdapter(payable(f));
        // Mint this address MAX_UINT AddressBook.DAI for stake
        deal(AddressBook.DAI, bob, type(uint256).max);

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

        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(AddressBook.PERMIT2, type(uint256).max);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.DAI);
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(fadapter), maturity, false, data);

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

    function testMainnetSponsorSeriesOnMockAdapterWhenPoolManagerZero() public {
        // 1. Set pool manager to zero address
        periphery.setPoolManager(address(0));

        // 2. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // Check that the PT and YT contracts have been deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));
    }

    /* ========== YT SWAPS ========== */

    function testMainnetSwapYTsForTarget() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 0.5 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 10% of bob's YTs for Target
        vm.startPrank(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);
        uint256 targetBalPre = mockTarget.balanceOf(bob);
        ERC20(yt).approve(AddressBook.PERMIT2, ytBalPre / 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), yt);
        periphery.swapYTsForTarget(address(mockAdapter), maturity, ytBalPre / 10, bob, data);
        uint256 ytBalPost = ERC20(yt).balanceOf(bob);
        uint256 targetBalPost = mockTarget.balanceOf(bob);

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

        uint256 targetBalPre = mockTarget.balanceOf(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW, // Min out is just the amount of Target borrowed
            // (if at least the Target borrowed is not swapped out, then we won't be able to pay back the flashloan)
            bob,
            data
        );
        uint256 targetBalPost = mockTarget.balanceOf(bob);
        uint256 ytBalPost = ERC20(yt).balanceOf(bob);

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
        vm.expectRevert("TRANSFER_FROM_FAILED");
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
        vm.expectRevert("TOO_MANY_TARGET_RETURNED");
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    function testMainnetSwapTargetForYTsMinOut() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;

        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW out from swapping TARGET_TO_BORROW / 2 + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW / 2, TARGET_TO_BORROW); // external call to catch the revert

        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
        // Check that we won't get TARGET_TO_BORROW * 1.01 out from swapping TARGET_TO_BORROW + TARGET_IN in
        this._checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW.fmul(1.01e18));

        // 3. Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        // Sanity check
        assertGt(targetReturnedPreview, 0);

        // Check that setting the min out to one more than the target we previewed fails
        vm.expectRevert("BAL#507"); // 507 = SWAP_LIMIT
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

        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW,
            msg.sender,
            data
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
        vm.etch(mockTarget.underlying(), address(newUnderlying).code);
        vm.etch(address(mockTarget), address(newMockTarget).code);

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
        vm.assume(initScale >= 1e9);
        vm.assume(scale >= initScale);

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
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(stake));
        vm.prank(bob);
        (pt, yt) = periphery.sponsorSeries(address(mockAdapter), maturity, false, data);
    }

    function _initializePool(
        uint256 maturity,
        ERC20 pt,
        uint256 targetToJoin,
        uint256 ptsToSwapIn
    ) public {
        // Issue some PTs (& YTs) we'll use to initialize the pool with
        uint256 targetToIssueWith = ptsToSwapIn.fdivUp(1e18 - mockAdapter.ifee()).fdivUp(mockAdapter.scale());
        mockTarget.mint(bob, targetToIssueWith + targetToJoin);

        vm.startPrank(bob);
        mockTarget.approve(address(divider), targetToIssueWith);
        Divider(divider).issue(address(mockAdapter), maturity, targetToIssueWith);
        // Sanity check that we have the PTs we need to swap in, either exactly, or close to (modulo rounding)
        assertTrue(pt.balanceOf(bob) >= ptsToSwapIn && pt.balanceOf(bob) <= ptsToSwapIn + 100);

        // Add Target to the Space pool
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        periphery.addLiquidityFromTarget(address(mockAdapter), maturity, targetToJoin, 1, 0, bob, data);

        // Swap PT balance in for Target to initialize the PT side of the pool
        pt.approve(AddressBook.PERMIT2, ptsToSwapIn);
        data = generatePermit(bobPrivKey, address(periphery), address(pt));
        periphery.swapPTsForTarget(address(mockAdapter), maturity, ptsToSwapIn, 0, bob, data);
        vm.stopPrank();
    }

    function _checkYTBuyingParameters(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            bob,
            data
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
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            msg.sender,
            data
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
