// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "solmate/erc20/SafeERC20.sol";
import { OracleLibrary } from "./external/OracleLibrary.sol";

// Internal references
import { BaseFeed as Feed } from "./feeds/BaseFeed.sol";
import { BaseFactory as Factory } from "./feeds/BaseFactory.sol";
import { GClaimManager } from "./modules/GClaimManager.sol";
import { Divider } from "./Divider.sol";
//import { PoolManager } from "./fuse/PoolManager.sol";

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

// TODO: to be removed when PoolManager is merged into here
interface PoolManager {
    function deployPool(string calldata name, bool whitelist, uint256 closeFactor, uint256 liqIncentive) external;
    function initTarget(address target) external;
    function initSeries(address feed, uint256 maturity) external;
}

/**
 * @title BasePriceOracle
 * @notice Returns prices of underlying tokens directly without the caller having to specify a cToken address.
 * @dev Implements the `PriceOracle` interface.
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 */
interface BasePriceOracle {
    /**
     * @notice Get the price of an underlying asset.
     * @param underlying The underlying asset to get the price of.
     * @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
     * Zero means the price is unavailable.
     */
    function price(address underlying) external view returns (uint);
}

/// @title Periphery contract
/// @notice You can use this contract to issue, combine, and redeem Sense ERC20 Zeros and Claims
contract Periphery {
    using SafeERC20 for ERC20;

    /// @notice Configuration
    uint24 public constant UNI_POOL_FEE = 10000; // denominated in hundredths of a bip
    uint32 public constant TWAP_PERIOD = 10 minutes; // ideal TWAP interval.

    /// @notice Mutable program state
    IUniswapV3Factory public immutable uniFactory;
    ISwapRouter public immutable uniSwapRouter;
    Divider public divider;
    PoolManager public poolManager;
    GClaimManager public gClaimManager;


    constructor(address _divider, address _poolManager, address _uniFactory, address _uniSwapRouter) {
        divider = Divider(_divider);
        poolManager = PoolManager(_poolManager);
        gClaimManager = new GClaimManager(_divider);
        uniFactory = IUniswapV3Factory(_uniFactory);
        uniSwapRouter = ISwapRouter(_uniSwapRouter);
        // TODO: maybe call deployPool() here

        // approve divider to withdraw stable assets
        ERC20(divider.stable()).approve(address(divider), type(uint256).max);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Sponsor a new Series
    /// @dev Calls divider to initalise a new series
    /// @dev Creates a UNIV3 pool for Zeros and Claims
    /// @dev Onboards Zero and Claim to Sense Fuse pool
    /// @param feed Feed to associate with the Series
    /// @param maturity Maturity date for the new Series, in units of unix time
    function sponsorSeries(address feed, uint256 maturity) external returns (address zero, address claim) {
        // transfer INIT_STAKE from sponsor into this contract
        uint256 convertBase = 1;
        uint256 stableDecimals = ERC20(divider.stable()).decimals();
        if (stableDecimals != 18) {
            convertBase = stableDecimals > 18 ? 10 ** (stableDecimals - 18) : 10 ** (18 - stableDecimals);
        }
        ERC20(divider.stable()).safeTransferFrom(msg.sender, address(this), divider.INIT_STAKE() / convertBase);
        (zero, claim) = divider.initSeries(feed, maturity, msg.sender);
        gClaimManager.join(feed, maturity, 0); // we join just to force the gclaim deployment
        address gclaim = address(gClaimManager.gclaims(claim));
        address unipool = IUniswapV3Factory(uniFactory).createPool(gclaim, zero, UNI_POOL_FEE); // deploy UNIV3 pool
        // TODO: IUniswapV3Pool(unipool).initialize(sqrtPriceX96);
//        poolManager.addSeries(feed, maturity);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Feed via the FeedFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address.
    /// @param target Target to onboard
    function onboardTarget(address factory, address target) external returns (address feedClone, address wtClone){
        (feedClone, wtClone) = Factory(factory).deployFeed(target);
        ERC20(target).approve(address(divider), type(uint256).max);
        //        poolManager.addTarget(target); // TODO add when merging pool manager
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @dev backfill amount refers to the excess that has accrued since the first Claim from a Series was deposited
    /// @dev in next versions will be calculate here. Refer to GClaimManager.excess() for more details about this value.
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit
    /// @param backfill Amount in target to backfill gClaims
    function swapTargetForZeros(address feed, uint256 maturity, uint256 tBal, uint256 backfill) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);

        // transfer target into this contract
        ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, address(this), tBal + backfill);

        // issue zeros & claims with target
        uint256 issued = divider.issue(feed, maturity, tBal);

        // convert claims to gclaims
        ERC20(claim).approve(address(gClaimManager), issued);
        gClaimManager.join(feed, maturity, issued);

        // swap gclaims to zeros
        address gclaim = address(gClaimManager.gclaims(claim));
        uint256 swapped = _swap(gclaim, zero, issued, address(this));

        // transfer issued + bought zeros to user
        ERC20(zero).transfer(msg.sender, issued + swapped);

    }

    function swapTargetForClaims(address feed, uint256 maturity, uint256 tBal) external {
        // transfer target into this contract
        ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, address(this), tBal);

        // issue zeros & claims with target
        uint256 issued = divider.issue(feed, maturity, tBal);

        // swap zeros to gclaims
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));
        uint256 swapped = _swap(zero, gclaim, issued, address(this));

        // convert gclaims to claims
        gClaimManager.exit(feed, maturity, swapped);

        // transfer issued + bought claims to user
        ERC20(claim).transfer(msg.sender, issued + swapped);
    }

    function swapZerosForTarget(address feed, uint256 maturity, uint256 zBal) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));

        // transfer zeros into this contract
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal);

        // get rate from uniswap
        uint256 rate = price(zero, gclaim);

        // swap some zeros for gclaims
        uint256 zerosToSell = zBal / (rate + 1); // TODO: is this equation correct?
        uint256 swapped = _swap(zero, gclaim, zerosToSell, address(this));

        // convert gclaims to claims
        gClaimManager.exit(feed, maturity, swapped);

        // combine zeros & claims
        divider.combine(feed, maturity, swapped);
    }

    function swapClaimsForTarget(address feed, uint256 maturity, uint256 cBal) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        address gclaim = address(gClaimManager.gclaims(claim));

        // transfer claims into this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // get rate from uniswap
        uint256 rate = price(zero, gclaim);

        // convert some gclaims to claims
        uint256 claimsToConvert = cBal / (rate + 1);
        gClaimManager.exit(feed, maturity, claimsToConvert);

        // swap gclaims for zeros
        uint256 swapped = _swap(gclaim, zero, claimsToConvert, address(this));

        // combine zeros & claims
        divider.combine(feed, maturity, swapped);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /* ========== VIEWS ========== */

    function price(address tokenA, address tokenB) public view returns (uint) {
        // Return tokenA/tokenB TWAP
        address pool = IUniswapV3Factory(uniFactory).getPool(tokenA, tokenB, UNI_POOL_FEE);
        int24 timeWeightedAverageTick = OracleLibrary.consult(pool, TWAP_PERIOD);
        uint128 baseUnit = uint128(10) ** uint128(ERC20(tokenA).decimals());
        uint256 quote = OracleLibrary.getQuoteAtTick(timeWeightedAverageTick, baseUnit, tokenA, tokenB);
        return quote * BasePriceOracle(msg.sender).price(tokenB) / (10 ** uint256(ERC20(tokenB).decimals())); // TODO: what's this
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, address recipient) internal returns (uint256 amountOut) {
        // approve router to spend tokenIn.
        ERC20(tokenIn).safeApprove(address(uniSwapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: UNI_POOL_FEE,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0, // TODO: use an oracle or other data source to choose a safer value for amountOutMinimum
                sqrtPriceLimitX96: 0 // set to be 0 to ensure we swap our exact input amount
        });

        amountOut = uniSwapRouter.exactInputSingle(params); // executes the swap
    }


    /* ========== MODIFIERS ========== */

    /* ========== EVENTS ========== */

}
