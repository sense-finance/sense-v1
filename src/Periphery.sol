// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { OracleLibrary } from "./external/OracleLibrary.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { FixedMath } from "./external/FixedMath.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// Internal references
import { Errors } from "./libs/Errors.sol";
import { BaseFeed as Feed } from "./feeds/BaseFeed.sol";
import { BaseFactory as Factory } from "./feeds/BaseFactory.sol";
import { GClaimManager } from "./modules/GClaimManager.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "./fuse/PoolManager.sol";

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;
    using Errors for string;

    /// @notice Configuration
    uint24 public constant UNI_POOL_FEE = 10000; // denominated in hundredths of a bip
    uint32 public constant TWAP_PERIOD = 10 minutes; // ideal TWAP interval.

    /// @notice Program state
    IUniswapV3Factory public immutable uniFactory;
    ISwapRouter public immutable uniSwapRouter;
    Divider public immutable divider;
    PoolManager public immutable poolManager;
    GClaimManager public immutable gClaimManager;
    mapping(address => bool) public factories;  // feed factories -> is supported

    constructor(address _divider, address _poolManager, address _uniFactory, address _uniSwapRouter) Trust(msg.sender) {
        divider = Divider(_divider);
        poolManager = PoolManager(_poolManager);
        gClaimManager = new GClaimManager(_divider);
        uniFactory = IUniswapV3Factory(_uniFactory);
        uniSwapRouter = ISwapRouter(_uniSwapRouter);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Sponsor a new Series
    /// @dev Calls divider to initalise a new series
    /// @dev Creates a UNIV3 pool for Zeros and Claims
    /// @dev Onboards Zero and Claim onto Sense Fuse pool
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    /// @param sqrtPriceX96 Initial price of the pool as a sqrt(token1/token0) Q64.96 value
    function sponsorSeries(
        address feed, uint256 maturity, uint160 sqrtPriceX96
    ) external returns (address zero, address claim) {
        (, , , address stake, uint256 stakeSize, ,) = Feed(feed).feedParams();

        // transfer stakeSize from sponsor into this contract
        uint256 convertBase = 1;
        uint256 stakeDecimals = ERC20(stake).decimals();
        if (stakeDecimals != 18) {
            convertBase = stakeDecimals > 18 ? 10 ** (stakeDecimals - 18) : 10 ** (18 - stakeDecimals);
        }
        ERC20(stake).safeTransferFrom(msg.sender, address(this), stakeSize / convertBase);

        // approve divider to withdraw stake assets
        ERC20(stake).approve(address(divider), type(uint256).max);

        (zero, claim) = divider.initSeries(feed, maturity, msg.sender);
        gClaimManager.join(feed, maturity, 0); // we join just to force the gclaim deployment
        address gclaim = address(gClaimManager.gclaims(claim));
        address unipool = IUniswapV3Factory(uniFactory).createPool(gclaim, zero, UNI_POOL_FEE); // deploy UNIV3 pool
        IUniswapV3Pool(unipool).initialize(sqrtPriceX96);
        poolManager.addSeries(feed, maturity);
        emit SeriesSponsored(feed, maturity, msg.sender);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Feed via the FeedFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address.
    /// @param target Target to onboard
    function onboardFeed(address factory, address target) external returns (address feedClone) {
        require(factories[factory], Errors.FactoryNotSupported);
        feedClone = Factory(factory).deployFeed(target);
        ERC20(target).approve(address(divider), type(uint256).max);
        poolManager.addTarget(target);
        emit FeedOnboarded(feedClone);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @dev backfill amount refers to the excess that has accrued since the first Claim from a Series was deposited
    /// @dev in next versions will be calculate here. Refer to GClaimManager.excess() for more details about this value.
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit
    /// @param backfill Amount in target to backfill gClaims
    function swapTargetForZeros(
        address feed, uint256 maturity, uint256 tBal,
        uint256 backfill, uint256 minAccepted
    ) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);

        // transfer target into this contract
        ERC20(Feed(feed).getTarget()).safeTransferFrom(msg.sender, address(this), tBal + backfill);

        // issue zeros & claims with target
        uint256 issued = divider.issue(feed, maturity, tBal);

        // convert claims to gclaims
        ERC20(claim).approve(address(gClaimManager), issued);
        gClaimManager.join(feed, maturity, issued);

        // swap gclaims to zeros
        address gclaim = address(gClaimManager.gclaims(claim));
        uint256 swapped = _swap(gclaim, zero, issued, address(this), minAccepted);
        uint256 totalZeros = issued + swapped;

        // transfer issued + bought zeros to user
        ERC20(zero).safeTransfer(msg.sender, totalZeros);

    }

    function swapTargetForClaims(address feed, uint256 maturity, uint256 tBal, uint256 minAccepted) external {
        // transfer target into this contract
        ERC20(Feed(feed).getTarget()).safeTransferFrom(msg.sender, address(this), tBal);

        // issue zeros & claims with target
        uint256 issued = divider.issue(feed, maturity, tBal);

        // swap zeros to gclaims
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));
        uint256 swapped = _swap(zero, gclaim, issued, address(this), minAccepted);

        // convert gclaims to claims
        gClaimManager.exit(feed, maturity, swapped);
        uint256 totalClaims = issued + swapped;

        // transfer issued + bought claims to user
        ERC20(claim).safeTransfer(msg.sender, totalClaims);
    }

    function swapZerosForTarget(address feed, uint256 maturity, uint256 zBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));

        // transfer zeros into this contract
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal);

        // get rate from uniswap
        uint256 rate = price(zero, gclaim);

        // swap some zeros for gclaims
        uint256 zerosToSell = zBal.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(zero).decimals());
        uint256 swapped = _swap(zero, gclaim, zerosToSell, address(this), minAccepted);

        // convert gclaims to claims
        gClaimManager.exit(feed, maturity, swapped);

        // combine zeros & claims
        uint256 tBal = divider.combine(feed, maturity, swapped);

        // transfer target to msg.sender
        ERC20(Feed(feed).getTarget()).safeTransfer(msg.sender, tBal);
    }

    function swapClaimsForTarget(address feed, uint256 maturity, uint256 cBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));

        // transfer claims into this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // get rate from uniswap
        uint256 rate = price(zero, gclaim);

        uint256 claimsToSell = cBal.fdiv(rate + 1 * 10**ERC20(zero).decimals(), 10**ERC20(zero).decimals());

        // convert some claims to gclaims
        ERC20 target = ERC20(Feed(feed).getTarget());
        ERC20(claim).approve(address(gClaimManager), claimsToSell);
        uint256 excess = gClaimManager.excess(feed, maturity, claimsToSell);
        target.safeTransferFrom(msg.sender, address(this), excess);
        target.approve(address(gClaimManager), excess);
        gClaimManager.join(feed, maturity, claimsToSell);

        // swap gclaims for zeros
        uint256 swapped = _swap(gclaim, zero, claimsToSell, address(this), minAccepted);

        // combine zeros & claims
        uint256 tBal = divider.combine(feed, maturity, swapped);

        // transfer target to msg.sender
        target.safeTransfer(msg.sender, tBal);
    }

    /* ========== VIEWS ========== */

    function price(address tokenA, address tokenB) public view returns (uint) {
        // return tokenA/tokenB TWAP
        address pool = IUniswapV3Factory(uniFactory).getPool(tokenA, tokenB, UNI_POOL_FEE);
        int24 timeWeightedAverageTick = OracleLibrary.consult(pool, TWAP_PERIOD);
        uint128 baseUnit = uint128(10) ** uint128(ERC20(tokenA).decimals());
        return OracleLibrary.getQuoteAtTick(timeWeightedAverageTick, baseUnit, tokenA, tokenB);
    }

    function _swap(
        address tokenIn, address tokenOut, uint256 amountIn,
        address recipient, uint256 minAccepted
    ) internal returns (uint256 amountOut) {
        // approve router to spend tokenIn
        ERC20(tokenIn).safeApprove(address(uniSwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: UNI_POOL_FEE,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAccepted,
                sqrtPriceLimitX96: 0 // set to be 0 to ensure we swap our exact input amount
        });

        amountOut = uniSwapRouter.exactInputSingle(params); // executes the swap
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @notice Enable or disable a factory
    /// @param factory Factory's address
    /// @param isOn Flag setting this factory to enabled or disabled
    function setFactory(address factory, bool isOn) external requiresTrust {
        require(factories[factory] != isOn, Errors.ExistingValue);
        factories[factory] = isOn;
        emit FactoryChanged(factory, isOn);
    }

    /* ========== EVENTS ========== */
    event FactoryChanged(address indexed feed, bool isOn);
    event SeriesSponsored(address indexed feed, uint256 indexed maturity, address indexed sponsor);
    event FeedOnboarded(address feed);
}
