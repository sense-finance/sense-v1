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
import { BaseTWrapper as TWrapper } from "./wrappers/BaseTWrapper.sol";

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;
    using Errors for string;

    enum Action {ZERO_TO_CLAIM, CLAIM_TO_TARGET}

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

        // approve divider to withdraw stable assets
        ERC20(Divider(_divider).stable()).approve(address(_divider), type(uint256).max);
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
        // transfer INIT_STAKE from sponsor into this contract
        uint256 convertBase = 1;
        uint256 stableDecimals = ERC20(divider.stable()).decimals();
        if (stableDecimals != 18) {
            convertBase = stableDecimals > 18 ? 10 ** (stableDecimals - 18) : 10 ** (18 - stableDecimals);
        }
        ERC20(divider.stable()).safeTransferFrom(msg.sender, address(this), divider.INIT_STAKE() / convertBase);
        (zero, claim) = divider.initSeries(feed, maturity, msg.sender);
        address unipool = IUniswapV3Factory(uniFactory).createPool(zero, Feed(feed).underlying(), UNI_POOL_FEE); // deploy UNIV3 pool
        IUniswapV3Pool(unipool).initialize(sqrtPriceX96);
        poolManager.addSeries(feed, maturity);
        emit SeriesSponsored(feed, maturity, msg.sender);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Feed via the FeedFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address.
    /// @param target Target to onboard
    function onboardTarget(address factory, address target) external returns (address feedClone, address wtClone) {
        require(factories[factory], Errors.FactoryNotSupported);
        (feedClone, wtClone) = Factory(factory).deployFeed(target);
        ERC20(target).approve(address(divider), type(uint256).max);
        ERC20(target).approve(wtClone, type(uint256).max); // for flashloans
        poolManager.addTarget(target);
        emit TargetOnboarded(target);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @dev backfill amount refers to the excess that has accrued since the first Claim from a Series was deposited
    /// @dev in next versions will be calculate here. Refer to GClaimManager.excess() for more details about this value.
    /// @param feed Feed address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit
    function swapTargetForZeros(
        address feed, uint256 maturity, uint256 tBal, uint256 minAccepted
    ) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);

        // transfer target directly to TWrapper for conversion
        ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, Feed(feed).twrapper(), tBal); // TODO: remove backfill param?

        // convert target to underlying
        uint256 uBal = TWrapper(Feed(feed).twrapper()).unwrapTarget(tBal);

        // swap underlying for zeros
        uint256 zBal = _swap(Feed(feed).underlying(), zero, uBal, address(this), minAccepted); // TODO: swap on yieldspace not uniswap

        // transfer bought zeros to user
        ERC20(zero).safeTransfer(msg.sender, zBal);

    }

    function swapTargetForClaims(address feed, uint256 maturity, uint256 tBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);

        // transfer target into this contract
        ERC20(Feed(feed).target()).safeTransferFrom(msg.sender, address(this), tBal);

        uint256 issued = divider.issue(feed, maturity, tBal);

        // (1) Sell zeros for underlying
        uint256 uBal = _swap(zero, Feed(feed).underlying(), issued, address(this), minAccepted); // TODO: swap on yieldspace not uniswap

        // (2) Convert underlying into target (on protocol)
        ERC20(Feed(feed).underlying()).safeTransfer(Feed(feed).twrapper(), uBal);
        uint256 wrappedTarget = TWrapper(Feed(feed).twrapper()).wrapUnderlying(uBal); // TODO: use method from protocol. Each TWrapper would know how to wrap underlying into target

        // (3) Calculate target needed to borrow in order to re-issue and obtain the desired amount of claims
        // Based on (1) we know the Zero price (uBal/issued) and we can infer the Claim price (1 - uBal/issued).
        // We can then calculate how many claims we can get with the underlying uBal (uBal / Claim price) and
        // finally, we get the target we need to borrow by doing a unit conversion from Claim to Target using the last
        // scale value.
        uint256 targetToBorrow;
        { // block scope to avoid stack too deep error
            uint256 lscale = divider.lscales(feed, maturity, address(this));
            ERC20 target = ERC20(Feed(feed).target());
            uint256 tBase = 10**target.decimals();
            uint256 cPrice = 1*tBase - (uBal.fdiv(issued, tBase)); // TODO: what if cPrice is 0 (e.g at maturity)?
            uint256 claimsAmount = uBal.fdiv(cPrice, tBase);
            targetToBorrow = claimsAmount.fdiv(lscale, 10**target.decimals()) - wrappedTarget;
        }

        // (4) Flash borrow target
        uint256 cBal = flashBorrow(abi.encode(Action.ZERO_TO_CLAIM), feed, maturity, targetToBorrow);

        // transfer claims from issuance + issued claims from borrowed target (step 4) to msg.sender (if applicable)
        ERC20(claim).safeTransfer(msg.sender, issued + cBal);
    }

    function swapZerosForTarget(address feed, uint256 maturity, uint256 zBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);

        // transfer zeros into this contract
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal);

        // swap zeros for underlying
        uint256 uBal = _swap(zero, Feed(feed).underlying(), zBal, address(this), minAccepted); // TODO: swap on yieldspace pool

        // wrap underlying into target
        ERC20(Feed(feed).underlying()).safeTransfer(Feed(feed).twrapper(), uBal);
        uint256 tBal = TWrapper(Feed(feed).twrapper()).wrapUnderlying(uBal);

        // transfer target to msg.sender
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);
    }

    function swapClaimsForTarget(address feed, uint256 maturity, uint256 cBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(feed, maturity);
        uint256 lscale = divider.lscales(feed, maturity, address(this));

        // transfer claims into this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // (1) Calculate target needed to borrow in order to be able to buy as many Zeros as Claims passed
        // On one hand, I get the price of the underlying/zero from Yieldspace pool
        // On the other hand, I know that I would need to purchase `cBal/2` Zeros so as to end up with same amount of
        // Zeros and Claims and be able to combine them into target
        uint256 targetToBorrow;
        {
            uint256 rate = price(Feed(feed).underlying(), zero); // price of underlying/zero from Yieldspace pool
            ERC20 target = ERC20(Feed(feed).target());
            uint256 tBase = 10**target.decimals();
            uint256 zBal = cBal.fdiv(2*tBase, tBase);
            uint256 uBal = zBal.fmul(rate, tBase);
            targetToBorrow = uBal.fmul(lscale, tBase); // amount of claims div 2 multiplied by rate gives me amount of underlying then multiplying by lscale gives me target
        }

        // (2) Flash borrow target
        uint256 tBal = flashBorrow(abi.encode(Action.CLAIM_TO_TARGET), feed, maturity, targetToBorrow);

        // (6) Part of the target repays the loan, part is transferred to msg.sender
        ERC20(Feed(feed).target()).safeTransfer(msg.sender, tBal);
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

    /* ========== INTERNAL & HELPER FUNCTIONS ========== */

    /// @notice Initiate a flash loan
    /// @param feed feed
    /// @param maturity maturity
    /// @param amount target amount to borrow
    /// @return claims issued with flashloan
    function flashBorrow(bytes memory data, address feed, uint256 maturity, uint256 amount) internal returns (uint256) {
        TWrapper twrapper = TWrapper(Feed(feed).twrapper());
        (bool result, uint256 value) = twrapper.flashLoan(data, address(this), feed, maturity, amount);
        require(result == true);
        return value;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(bytes calldata data, address initiator, address feed, uint256 maturity, uint256 amount) external returns(bytes32, uint256) {
        require(msg.sender == address(Feed(feed).twrapper()), Errors.FlashUntrustedBorrower);
        require(initiator == address(this), Errors.FlashUntrustedLoanInitiator);
        (address zero, , , , , , , ,) = divider.series(feed, maturity);
        (Action action) = abi.decode(data, (Action));
        if (action == Action.ZERO_TO_CLAIM) {

            // (5) Issue
            uint256 issued = divider.issue(feed, maturity, amount);

            // (6) Sell Zeros for underlying
            uint256 uBal = _swap(zero, Feed(feed).underlying(), issued, address(this), 0); // TODO: minAccepted
            // uint256 uBal = _swap(zero, Feed(feed).underlying(), issued, address(this), minAccepted); // TODO: swap on yieldspace

            // (7) Convert underlying into target
            ERC20(Feed(feed).underlying()).safeTransfer(Feed(feed).twrapper(), uBal);
            TWrapper(Feed(feed).twrapper()).wrapUnderlying(uBal); // TODO: use method from protocol (different interfaces for different protocols). Maybe mint on Feed or Wrapper?
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), issued);

        } else if (action == Action.CLAIM_TO_TARGET) {
            // (3) Convert target into underlying (unwrap via protocol)
            uint256 uBal = TWrapper(Feed(feed).twrapper()).unwrapTarget(amount); // TODO: use method from protocol (different interfaces for different protocols). Maybe mint on Feed or Wrapper?

            // (4) Swap underlying for Zeros on Yieldspace pool
            uint256 zBal = _swap(Feed(feed).underlying(), zero, uBal, address(this), 0); // TODO: minAccepted param

            // (5) Combine zeros and claim
            uint256 tBal = divider.combine(feed, maturity, zBal);
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
        }
        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), 0);
    }

    /* ========== EVENTS ========== */
    event FactoryChanged(address indexed feed, bool isOn);
    event SeriesSponsored(address indexed feed, uint256 indexed maturity, address indexed sponsor);
    event TargetOnboarded(address target);
}
