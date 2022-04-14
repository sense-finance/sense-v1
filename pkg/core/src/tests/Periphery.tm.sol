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
        uint256 g1 = uint256(950) * 1e18 / uint256(1000);
        uint256 g2 = uint256(1000) * 1e18 / uint256(950);
        SpaceFactoryLike(spaceFactory).setParams(ts, g1, g2, true);
        hevm.stopPrank(); // Stop prank calling

        periphery.onboardAdapter(address(mockAdapter), true);
        periphery.verifyAdapter(address(mockAdapter), true);
    }
}

contract PeripheryTests is PeripheryTestHelper {
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

        // 2. Issue some PTs & YTs
        mockTarget.mint(address(this), 1e18);
        mockTarget.approve(address(divider), 0.5e18);
        Divider(divider).issue(address(mockAdapter), maturity, 0.5e18);

        // 3. Add 0.5e18 Target to the Space pool
        mockTarget.approve(address(periphery), 0.5e18);
        periphery.addLiquidityFromTarget(address(mockAdapter), maturity, 0.5e18, 1, 0);

        // 4. Swap PT balance in for Target to initialize the PT side of the pool
        ERC20(pt).approve(address(periphery), ERC20(pt).balanceOf(address(this)));
        periphery.swapPTsForTarget(address(mockAdapter), maturity, ERC20(pt).balanceOf(address(this)), 0);

        // 5. Swap 10% of this address' YTs for Target
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

    function testMainnetSwapTargetForYTsOne() public {
        // 1. Set adapter scale to 1
        mockAdapter.setScale(1e18);

        // 2. Sponsor a Series
        (uint256 maturity, address pt, address yt) = _sponsorSeries();

        // 3. Issue some PTs & YTs
        mockTarget.mint(address(this), 2e18);
        mockTarget.approve(address(divider), 1e18);
        Divider(divider).issue(address(mockAdapter), maturity, 1e18);
        // Sanity check that scale is 1 and there is no issuance fee. ie PTs are issued 1:1 for Target
        assertEq(ERC20(pt).balanceOf(address(this)), 1e18);

        // 4. Add 0.5e18 Target to the Space pool
        mockTarget.approve(address(periphery), 1e18);
        periphery.addLiquidityFromTarget(address(mockAdapter), maturity, 1e18, 1, 0);

        // 5. Swap PT balance in for Target to initialize the PT side of the pool
        ERC20(pt).approve(address(periphery), 0.5e18);
        periphery.swapPTsForTarget(address(mockAdapter), maturity, 0.5e18, 0);

        // 6. Swap 0.005 of this address' Target for YTs
        mockTarget.approve(address(periphery), 0.005e18);
        uint256 targetBalPre = mockTarget.balanceOf(address(this));
        uint256 ytBalPre = ERC20(yt).balanceOf(address(this));
        uint256 TARGET_TO_SWAP = 0.005e18;
        uint256 TARGET_TO_BORROW = 0.048367e18; // Calculated using sense-v1/pkg/yt-buying-lib
        (uint256 targetBack, uint256 ytsOut) = periphery.swapTargetForYTs(
            address(mockAdapter),
            maturity,
            TARGET_TO_SWAP,
            TARGET_TO_BORROW,
            TARGET_TO_BORROW * 0.999e18 / 1e18 // Min out is just below the amount of Target borrowed 
            // (we expect the estimated amount to borrow to be near the optimial answer, but just a little lower)
        );
        uint256 targetBalPost = mockTarget.balanceOf(address(this));
        uint256 ytBalPost = ERC20(yt).balanceOf(address(this));

        // Check that the return values reflect the token balance changes
        assertEq(targetBalPre - targetBalPost + targetBack, TARGET_TO_SWAP);
        assertEq(ytBalPost - ytBalPre, ytsOut);
        // Check that the YTs returned are the result of issuing from the borrowed Target + transferred Target
        assertEq(ytsOut, TARGET_TO_SWAP + TARGET_TO_BORROW);

        // Check that we got less than 0.000001 Target back
        assertTrue(targetBack < 0.000001e18);

        // TODO violated min out
        // TODO min out being a proxy max target received
        // TODO borrow amount too large (cant pay back)

        // address pool = SpaceFactoryLike(spaceFactory).pools(address(mockAdapter), maturity);
        // (, uint256[] memory balances, ) = BalancerVault(balancerVault).getPoolTokens(BalancerPool(pool).getPoolId());
        // ERC20(pt).approve(address(periphery), 0.0001e18);
        // emit log_uint(periphery.swapPTsForTarget(address(mockAdapter), maturity, 0.0001e18, 0));
    }

    // INTERNAL HELPERS ––––––––––––

    function _sponsorSeries()
        internal
        returns (
            uint256 maturity,
            address pt,
            address yt
        )
    {
        (uint256 year, uint256 month, ) = DateTimeFull.timestampToDate(block.timestamp);
        maturity = DateTimeFull.timestampFromDateTime(
            year + 1,
            month,
            1,
            0,
            0,
            0
        );

        (pt, yt) = periphery.sponsorSeries(address(mockAdapter), maturity, false);
    }
}
