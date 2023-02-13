// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import { FixedMath } from "../external/FixedMath.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

// Internal references
import { Periphery, IERC20 } from "../Periphery.sol";
import { PoolManager } from "@sense-finance/v1-fuse/PoolManager.sol";
import { Divider } from "../Divider.sol";
import { BaseFactory } from "../adapters/abstract/factories/BaseFactory.sol";
import { BaseAdapter } from "../adapters/abstract/BaseAdapter.sol";
import { CAdapter } from "../adapters/implementations/compound/CAdapter.sol";
import { FAdapter } from "../adapters/implementations/fuse/FAdapter.sol";
import { CFactory } from "../adapters/implementations/compound/CFactory.sol";
import { FFactory } from "../adapters/implementations/fuse/FFactory.sol";
import { WstETHLike } from "../adapters/implementations/lido/WstETHAdapter.sol";

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
        bool _oracleEnabled,
        bool _balancerFeesEnabled
    ) external;
}

// Periphery contract wit _fillQuote exposed for testing
contract PeripheryFQ is Periphery {
    constructor(
        address _divider,
        address _poolManager,
        address _spaceFactory,
        address _balancerVault,
        address _permit2,
        address _exchangeProxy
    ) Periphery(_divider, _poolManager, _spaceFactory, _balancerVault, _permit2, _exchangeProxy) {}

    function fillQuote(SwapQuote calldata quote) public payable returns (uint256 boughtAmount) {
        return _fillQuote(quote);
    }
}

contract PeripheryTestHelper is ForkTest, Permit2Helper {
    uint256 public origin;

    PeripheryFQ internal periphery;

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

        // some tests are using an existing Series so we want to fix the block number
        // string memory url = vm.rpcUrl("mainnet");
        // uint256 forkId = vm.createFork(url);
        // vm.selectFork(forkId);
        vm.rollFork(16583087); // Feb-08-2023 09:12:23 AM +UTC
        // assertEq(block.number, 16583087);

        origin = block.timestamp;
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        uint256 firstDayOfMonth = DateTimeFull.timestampFromDateTime(year, month, 1, 0, 0, 0);
        vm.warp(firstDayOfMonth); // Set to first day of the month

        MockToken underlying = new MockToken("TestUnderlying", "TU", 18);
        mockTarget = new MockTarget(address(underlying), "TestTarget", "TT", 18);

        // Mainnet contracts
        divider = AddressBook.DIVIDER_1_2_0;
        spaceFactory = AddressBook.SPACE_FACTORY_1_3_0;
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
        periphery = new PeripheryFQ(
            divider,
            poolManager,
            spaceFactory,
            balancerVault,
            address(permit2),
            AddressBook.EXCHANGE_PROXY
        );

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
        SpaceFactoryLike(spaceFactory).setParams(ts, g1, g2, true, false);

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
        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
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

        // Mint bob MAX_UINT AddressBook.DAI (for stake)
        deal(AddressBook.DAI, bob, type(uint256).max);

        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(AddressBook.PERMIT2, type(uint256).max);

        Periphery.SwapQuote memory quote = _getQuote(address(cadapter), AddressBook.DAI, AddressBook.DAI);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), AddressBook.DAI);
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data, quote);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    function testMainnetSponsorSeriesOnCAdapter2() public {
        // We roll back to original block number (which is the latest block) because the call chainlink's oracle
        // somehow is not being done taking into consideration the warped block (maybe a bug in foundry?)
        vm.warp(origin);
        CAdapter cadapter = CAdapter(payable(periphery.deployAdapter(address(cfactory), AddressBook.cBAT, "")));

        // Calculate maturity
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

        // Mint bob MAX_UINT AddressBook.DAI (for stake)
        deal(AddressBook.DAI, bob, type(uint256).max);

        // Approve Periphery to pull DAI (stake)
        vm.prank(bob);
        ERC20(AddressBook.DAI).approve(address(periphery), type(uint256).max);

        Periphery.SwapQuote memory quote = _getQuote(address(cadapter), AddressBook.DAI, AddressBook.DAI);
        Periphery.PermitData memory data; // sending empty data because we are using normal approval
        vm.prank(bob);
        (address pt, address yt) = periphery.sponsorSeries(address(cadapter), maturity, false, data , quote);

        // Check pt and yt deployed
        assertTrue(pt != address(0));
        assertTrue(yt != address(0));

        // Check PT and YT onboarded on PoolManager (Fuse)
        (PoolManager.SeriesStatus status, ) = PoolManager(poolManager).sSeries(address(cadapter), maturity);
        assertTrue(status == PoolManager.SeriesStatus.QUEUED);
    }

    // TODO: from ETH and from other TOKEN
    function testMainnetSponsorSeriesOnCAdapterFromETH() public {
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
        (address pt, address yt) = periphery.sponsorSeries(
            address(fadapter),
            maturity,
            false,
            data,
            _getQuote(address(fadapter), AddressBook.DAI, AddressBook.DAI)
        );

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

    /* ========== PT SWAPS ========== */

    function testMainnetSwapAllForPTs() public {
        // Get existing adapter (wstETH adapter)
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        // 1. Swap DAI for PTs
        ERC20 token = ERC20(AddressBook.DAI);
        uint256 amt = 10**token.decimals(); // 1 DAI
        // Create quote from 0x API to do a 0.1 DAI to underlying swap
        Periphery.SwapQuote memory quote = _getQuote(adapter, address(token), address(0));
        _swapTokenForPTs(adapter, maturity, quote, amt);

        // 2. Swap target for PTs
        ERC20 target = ERC20(MockAdapter(adapter).target());
        amt = 10**(target.decimals() - 1); // 0.1 target
        quote = _getQuote(adapter, address(target), address(0));
        _swapTokenForPTs(adapter, maturity, quote, amt);

        // 3. Swap underlying for PTs
        ERC20 underlying = ERC20(MockAdapter(adapter).underlying());
        amt = 10**(underlying.decimals() - 1); // 0.1 underlying
        quote = _getQuote(adapter, address(underlying), address(0));
        _swapTokenForPTs(adapter, maturity, quote, amt);
    }

    function testMainnetSwapPTsForAll() public {
        // Get existing adapter (wstETH adapter)
        (address adapter, uint256 maturity) = _getExistingAdapterAndSeries();

        // // 1. Swap PTs for target
        Periphery.SwapQuote memory quote = _getQuote(adapter, address(0), MockAdapter(adapter).target());
        // _swapPTs(adapter, maturity, quote);

        // // 2. Swap PTs for underlying
        // quote = _getQuote(adapter, address(0), MockAdapter(adapter).underlying());
        // _swapPTs(adapter, maturity, quote);

        // 3. Swap PTs for DAI
        // Create 0x API quote to do a X underlying to token swap
        // X is the amount of underlying resulting from the swap of PTs that we will be selling on 0x
        quote = _getQuote(adapter, address(0), AddressBook.DAI);
        _swapPTs(adapter, maturity, quote);
    }

    /* ========== YT SWAPS ========== */

    function testMainnetSwapYTsForTarget() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 2. Initialize the pool by joining 0.5 Target in, then swapping 0.5 PTs in for Target
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 10% of bob's YTs for Target
        vm.startPrank(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);
        uint256 targetBalPre = mockTarget.balanceOf(bob);
        ERC20(yt).approve(AddressBook.PERMIT2, ytBalPre / 10);
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), yt);
        periphery.swapYTs(
            address(mockAdapter),
            maturity,
            ytBalPre / 10,
            bob,
            data,
            _getQuote(address(mockAdapter), address(0), address(mockTarget))
        );
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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // 3. Swap 0.005 of this address' Target for YTs
        uint256 TARGET_IN = 0.0234e18;
        // Calculated using sense-v1/yt-buying-lib
        uint256 TARGET_TO_BORROW = 0.1413769e18;

        uint256 targetBalPre = mockTarget.balanceOf(bob);
        uint256 ytBalPre = ERC20(yt).balanceOf(bob);

        Periphery.SwapQuote memory quote = _getQuote(address(mockAdapter), address(mockTarget), address(0));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW, // Min out is just the amount of Target borrowed
            // (if at least the Target borrowed is not swapped out, then we won't be able to pay back the flashloan)
            bob,
            data,
            quote
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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.03340541e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckTwo() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.01e18;
        uint256 TARGET_TO_BORROW = 0.06489898e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckThree() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowCheckFour() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib
        uint256 TARGET_IN = 0.00003e18;
        uint256 TARGET_TO_BORROW = 0.0002066353449e18;
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);
    }

    function testMainnetSwapTargetForYTsBorrowTooMuch() public {
        // 1. Sponsor a Series
        (uint256 maturity, address pt, ) = _sponsorSeries();

        // 2. Initialize the pool by joining 1 Target in, then swapping 0.5 PTs in for Target
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 1e18, 0.5e18);

        uint256 TARGET_IN = 0.0234e18;
        uint256 TARGET_TO_BORROW = 0.1413769e18;
        uint256 TARGET_TRANSFERRED_IN = 0.5e18;

        // Get the Target amount we'd get back from buying YTs with these set params, then revert any state changes
        (uint256 targetReturnedPreview, ) = _callStaticBuyYTs(maturity, TARGET_IN, TARGET_TO_BORROW, TARGET_TO_BORROW);

        mockTarget.mint(address(periphery), TARGET_TRANSFERRED_IN);

        Periphery.SwapQuote memory quote = _getQuote(address(mockAdapter), address(mockTarget), address(0));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            TARGET_IN,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW,
            msg.sender,
            data,
            quote
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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), 10**targetDecimals, 10**targetDecimals / 2);

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
        _initializePool(address(mockAdapter), maturity, ERC20(pt), uint256(1e18).fdivUp(initScale), 0.5e18);

        // 4. Update scale
        mockAdapter.setScale(scale);

        // Check buying YT swap params calculated using sense-v1/yt-buying-lib, adjusted with the current scale
        uint256 TARGET_IN = uint256(0.0234e18).fdivUp(scale);
        uint256 TARGET_TO_BORROW = uint256(0.1413769e18).fdivUp(scale);
        _checkYTBuyingParameters(maturity, TARGET_IN, TARGET_TO_BORROW, 0);
    }

    /* ========== ZAPS: FILL QUOTE ========== */

    function testMainnetFillQuote() public {
        // USDC to DAI
        deal(AddressBook.USDC, address(periphery), 1e6);
        Periphery.SwapQuote memory quote = Periphery.SwapQuote({
            sellToken: IERC20(AddressBook.USDC),
            buyToken: IERC20(AddressBook.DAI),
            spender: 0xDef1C0ded9bec7F1a1670819833240f027b25EfF, // from 0x API
            swapTarget: payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF), // from 0x API
            // https://api.0x.org/swap/v1/quote?sellToken=USDC&buyToken=DAI&sellAmount=1000000
            swapCallData: hex"d9627aa4000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000db564da66189a7b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000006b175474e89094c44da98b954eedeac495271d0f869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000007d84779f8863e3ed0c"
        });
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.USDC, AddressBook.DAI, 0);
        uint256 daiBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(periphery));
        uint256 usdcBalanceBefore = ERC20(AddressBook.USDC).balanceOf(address(periphery));
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.USDC).balanceOf(address(periphery)), usdcBalanceBefore - 1e6);
        assertGt(ERC20(AddressBook.DAI).balanceOf(address(periphery)), daiBalanceBefore);

        // DAI to wstETH
        deal(AddressBook.DAI, address(periphery), 1e18);
        quote.sellToken = IERC20(AddressBook.DAI);
        quote.buyToken = IERC20(AddressBook.WSTETH);
        quote.spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // from 0x API
        quote.swapTarget = payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF); // from 0x API
        // https://api.0x.org/swap/v1/quote?sellToken=DAI&buyToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&sellAmount=1000000000000000000
        quote
            .swapCallData = hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000001e64c4e19add2000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000d993111fd763e3f3d5";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.DAI, AddressBook.WSTETH, 0);
        daiBalanceBefore = ERC20(AddressBook.DAI).balanceOf(address(periphery));
        uint256 wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(periphery));
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.DAI).balanceOf(address(periphery)), daiBalanceBefore - 1e18);
        assertGt(ERC20(AddressBook.WSTETH).balanceOf(address(periphery)), wstETHBalanceBefore);

        // wstETH to ETH
        deal(AddressBook.WSTETH, address(periphery), 1e18);
        vm.prank(address(periphery));
        quote.sellToken = IERC20(AddressBook.WSTETH);
        quote.buyToken = IERC20(periphery.ETH());
        quote.spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // from 0x API
        quote.swapTarget = payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF); // from 0x API
        // https://api.0x.org/swap/v1/quote?sellToken=0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0&buyToken=ETH&sellAmount=1000000000000000000
        quote
            .swapCallData = hex"803ba26d00000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000f355119a94095420000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b7f39c581f595b53c5cb19bd0b3f8da6c935e2ca00001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000002fffadbf5163e3f059";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(AddressBook.WSTETH, periphery.ETH(), 0);
        wstETHBalanceBefore = ERC20(AddressBook.WSTETH).balanceOf(address(periphery));
        uint256 ethBalanceBefore = address(periphery).balance;
        periphery.fillQuote(quote);
        assertEq(ERC20(AddressBook.WSTETH).balanceOf(address(periphery)), wstETHBalanceBefore - 1e18);
        assertGt(address(periphery).balance, ethBalanceBefore);

        // ETH to USDC
        deal(address(periphery), 1 ether);
        quote.sellToken = IERC20(periphery.ETH());
        quote.buyToken = IERC20(AddressBook.USDC);
        quote.spender = 0x0000000000000000000000000000000000000000; // from 0x API
        quote.swapTarget = payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF); // from 0x API
        // https://api.0x.org/swap/v1/quote?sellToken=ETH&buyToken=USDC&sellAmount=1000000000000000000
        quote
            .swapCallData = hex"d9627aa400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000006138608500000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000001b18fd746963e3ed22";
        vm.expectEmit(true, true, false, false);
        emit BoughtTokens(periphery.ETH(), AddressBook.USDC, 0);
        ethBalanceBefore = address(periphery).balance;
        usdcBalanceBefore = ERC20(AddressBook.USDC).balanceOf(address(periphery));
        vm.prank(address(periphery));
        periphery.fillQuote{ value: 1 ether }(quote);
        assertEq(address(periphery).balance, ethBalanceBefore - 1 ether);
        assertGt(ERC20(AddressBook.USDC).balanceOf(address(periphery)), usdcBalanceBefore);
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
        (pt, yt) = periphery.sponsorSeries(
            address(mockAdapter),
            maturity,
            false,
            data,
            _getQuote(address(mockAdapter), address(stake), address(stake))
        );
    }

    function _initializePool(
        address adapter,
        uint256 maturity,
        ERC20 pt,
        uint256 targetToJoin,
        uint256 ptsToSwapIn
    ) public {
        MockTarget target = MockTarget(MockAdapter(adapter).target());

        {
            // Issue some PTs (& YTs) we'll use to initialize the pool with
            uint256 targetToIssueWith = ptsToSwapIn.fdivUp(1e18 - MockAdapter(adapter).ifee()).fdivUp(
                MockAdapter(adapter).scale()
            );
            deal(address(target), bob, targetToIssueWith + targetToJoin);

            vm.startPrank(bob);
            target.approve(address(divider), targetToIssueWith);
            Divider(divider).issue(adapter, maturity, targetToIssueWith);
            // Sanity check that we have the PTs we need to swap in, either exactly, or close to (modulo rounding)
            assertTrue(pt.balanceOf(bob) >= ptsToSwapIn && pt.balanceOf(bob) <= ptsToSwapIn + 100);
        }

        {
            // Add Target to the Space pool
            periphery.addLiquidity(
                adapter,
                maturity,
                targetToJoin,
                1,
                0,
                bob,
                generatePermit(bobPrivKey, address(periphery), address(target)),
                _getQuote(address(adapter), address(target), address(0))
            );
        }

        {
            // Swap PT balance in for Target to initialize the PT side of the pool
            pt.approve(AddressBook.PERMIT2, ptsToSwapIn);
            Periphery.SwapQuote memory quote = _getQuote(address(adapter), address(0), address(target));
            periphery.swapPTs(
                adapter,
                maturity,
                ptsToSwapIn,
                0,
                bob,
                generatePermit(bobPrivKey, address(periphery), address(pt)),
                quote
            );
        }

        vm.stopPrank();
    }

    function _checkYTBuyingParameters(
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut
    ) public {
        Periphery.SwapQuote memory quote = _getQuote(address(mockAdapter), address(mockTarget), address(0));
        Periphery.PermitData memory permit = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            bob,
            permit,
            quote
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
        Periphery.SwapQuote memory quote = _getQuote(address(mockAdapter), address(mockTarget), address(0));
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(mockTarget));
        vm.prank(bob);
        (uint256 targetReturned, uint256 ytsOut) = periphery.swapForYTs(
            address(mockAdapter),
            maturity,
            targetIn,
            targetToBorrow,
            minOut,
            msg.sender,
            data,
            quote
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

    function _getExistingAdapterAndSeries() public returns (address adapter, uint256 maturity) {
        // TODO: replace for const
        adapter = 0x6fC4843aac4786b4420e954a2271BE16f225a482; // wstETH adapter
        maturity = 1811808000; // June 1st 2027

        // 1. Set Divider as unguarded
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setGuarded(false);

        // 2. Set Periphery on Divider
        vm.prank(AddressBook.SENSE_MULTISIG);
        Divider(divider).setPeriphery(address(periphery));

        // 3. Onboard & Verify adapter into Periphery
        periphery.onboardAdapter(adapter, false);
        periphery.verifyAdapter(adapter, false);
    }

    function _getQuote(
        address adapter,
        address fromToken,
        address toToken
    ) public returns (Periphery.SwapQuote memory quote) {
        if (fromToken == toToken) {
            quote.sellToken = IERC20(fromToken);
            quote.buyToken = IERC20(toToken);
            return quote;
        }
        MockAdapter adapter = MockAdapter(adapter);
        if (fromToken == address(0)) {
            if (toToken == adapter.underlying() || toToken == adapter.target()) {
                // Create a quote where we only fill the buyToken (with target or underlying) and the rest
                // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
                quote.buyToken = IERC20(toToken);
            } else {
                // Quote to swap underlying for token via 0x
                address underlying = MockAdapter(adapter).underlying();
                quote.sellToken = IERC20(underlying);
                quote.buyToken = IERC20(toToken);
                quote.spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // from 0x API
                quote.swapTarget = payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF); // from 0x API
                // https://api.0x.org/swap/v1/quote?sellToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&buyToken=DAI&sellAmount=957048107692151
                quote
                    .swapCallData = hex"415565b0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000141618cc9529b7c200000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003a00000000000000000000000000000000000000000000000000000000000000760000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002600000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000154c69646f0000000000000000000000000000000000000000000000000000000000000000000000000003666e207df077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000360000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000032000000000000000000000000000000000000000000000000000000000000002e0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e6973776170563300000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000141618cc9529b7c2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000427f39c581f595b53c5cb19bd0b3f8da6c935e2ca00001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000646b175474e89094c44da98b954eedeac495271d0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd000000000000000000000000100000000000000000000000000000000000001100000000000000000000000000000000000000000000004ca866b2c363ea5e3e";
            }
        } else {
            if (fromToken == adapter.underlying() || fromToken == adapter.target()) {
                // Create a quote where we only fill the sellToken (with target or underlying) and the rest
                // is empty. This is used by the Periphery so it knows it does not have to perform a swap.
                quote.sellToken = IERC20(fromToken);
            } else {
                // Quote to swap token for underlying via 0x
                address underlying = MockAdapter(adapter).underlying();
                quote.sellToken = IERC20(fromToken);
                quote.buyToken = IERC20(underlying);
                quote.spender = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF; // from 0x API
                quote.swapTarget = payable(0xDef1C0ded9bec7F1a1670819833240f027b25EfF); // from 0x API
                // https://api.0x.org/swap/v1/quote?sellToken=DAI&buyToken=0xae7ab96520de3a18e5e111b5eaab095312d7fe84&sellAmount=1000000000000000000
                quote
                    .swapCallData = hex"415565b00000000000000000000000006b175474e89094c44da98b954eedeac495271d0f000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000000000000000000000000000000de0b6b3a764000000000000000000000000000000000000000000000000000000021adf49ed07e000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000740000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000340000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000002c00000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000002537573686953776170000000000000000000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000d9e1ce17f2641f24ae83637ab66a2cca9c378b9f000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000020000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe84000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000002a00000000000000000000000000000000000000000000000000000000000000260ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000154c69646f000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000021adf49ed07e000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000ae7ab96520de3a18e5e111b5eaab095312d7fe840000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000030000000000000000000000006b175474e89094c44da98b954eedeac495271d0f0000000000000000000000007f39c581f595b53c5cb19bd0b3f8da6c935e2ca0000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000b67119692563e364e7";
            }
        }
    }

    function _swapTokenForPTs(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote,
        uint256 amt
    ) public {
        ERC20 token = ERC20(address(quote.sellToken));

        // 0. Get PT address
        (address pt, , , , , , , , ) = Divider(divider).series(adapter, maturity);

        // 1. Load token into Bob's address
        if (address(token) == AddressBook.STETH) {
            // get steth by unwrapping wsteth because `deal()` won't work
            deal(AddressBook.WSTETH, bob, amt);
            vm.prank(bob);
            WstETHLike(AddressBook.WSTETH).unwrap(amt);
        } else {
            deal(address(token), bob, amt);
        }

        // 2. Approve PERMIT2 to spend token
        vm.prank(bob);
        token.approve(AddressBook.PERMIT2, type(uint256).max);

        // 3. Generate permit message and signature
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), address(token));

        // 4. Swap Token for PTs
        uint256 ptBalPre = ERC20(pt).balanceOf(bob);
        uint256 tokenBalPre = token.balanceOf(bob);

        // assert we've swapped tokens through 0x
        if (address(quote.sellToken) != address(0) && address(quote.buyToken) != address(0)) {
            vm.expectEmit(true, true, true, true);
            emit BoughtTokens(address(token), MockAdapter(adapter).underlying(), 598481084566980);
        }

        vm.prank(bob);
        uint256 ptBal = periphery.swapForPTs(adapter, maturity, amt, 0, bob, data, quote);

        uint256 tokenBalPost = token.balanceOf(bob);
        uint256 ptBalPost = ERC20(pt).balanceOf(bob);

        // Check that the return values reflect the token balance changes
        assertEq(tokenBalPre, tokenBalPost + amt);
        assertEq(ptBalPost, ptBalPre + ptBal);
    }

    function _swapPTs(
        address adapter,
        uint256 maturity,
        Periphery.SwapQuote memory quote
    ) public {
        ERC20 token = ERC20(address(quote.buyToken));
        // 0. Get PT address
        (address pt, , , , , , , , ) = Divider(divider).series(adapter, maturity);
        ERC20 ptToken = ERC20(pt);

        // 1. Approve PERMIT2 to spend PTs
        vm.prank(bob);
        ptToken.approve(AddressBook.PERMIT2, type(uint256).max);

        {
            // 2. Issue PTs from 1 target
            ERC20 target = ERC20(MockAdapter(adapter).target());
            uint256 amt = 1 * 10**(target.decimals() - 1);
            deal(address(target), bob, amt);
            vm.prank(bob);
            target.approve(divider, type(uint256).max);
            vm.prank(bob);
            Divider(divider).issue(adapter, maturity, amt);
        }

        // 3. Generate permit message and signature
        Periphery.PermitData memory data = generatePermit(bobPrivKey, address(periphery), pt);

        {
            // 4. Swap PTs for Token
            uint256 ptBalPre = ERC20(pt).balanceOf(bob);
            uint256 tokenBalPre = token.balanceOf(bob);

            // assert we've swapped tokens through 0x
            if (address(quote.sellToken) != address(0) && address(quote.buyToken) != address(0)) {
                vm.expectEmit(true, true, false, false);
                emit BoughtTokens(MockAdapter(adapter).underlying(), address(token), 0);
            }

            vm.prank(bob);
            uint256 tokenBal = periphery.swapPTs(adapter, maturity, ptBalPre, 0, bob, data, quote);
            uint256 tokenBalPost = token.balanceOf(bob);
            uint256 ptBalPost = ERC20(pt).balanceOf(bob);

            // Check that the return values reflect the token balance changes
            assertEq(ptBalPost, 0);
            assertApproxEqAbs(tokenBalPre, tokenBalPost + 1 - tokenBal, 1); // +1 because of Lido's 1 wei corner case: https://docs.lido.fi/guides/steth-integration-guide#1-wei-corner-case
        }
    }

    // required for refunds
    receive() external payable {}

    /* ========== LOGS ========== */

    event BoughtTokens(address indexed sellToken, address indexed buyToken, uint256 indexed boughtAmount);
}
