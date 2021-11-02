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
import { CropAdapter as Adapter } from "./adapters/CropAdapter.sol";
import { BaseFactory as Factory } from "./adapters/BaseFactory.sol";
import { GClaimManager } from "./modules/GClaimManager.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "./fuse/PoolManager.sol";
import { Token } from "./tokens/Token.sol";

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
    mapping(address => bool) public factories;  // adapter factories -> is supported

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
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    /// @param sqrtPriceX96 Initial price of the pool as a sqrt(token1/token0) Q64.96 value
    function sponsorSeries(
        address adapter, uint256 maturity, uint160 sqrtPriceX96
    ) external returns (address zero, address claim) {
        (, , , , address stake, uint256 stakeSize, ,) = Adapter(adapter).adapterParams();

        // transfer stakeSize from sponsor into this contract
        uint256 stakeDecimals = ERC20(stake).decimals();
        ERC20(stake).safeTransferFrom(msg.sender, address(this), stakeSize / convertBase(stakeDecimals));

        // approve divider to withdraw stake assets
        ERC20(stake).approve(address(divider), type(uint256).max);

        (zero, claim) = divider.initSeries(adapter, maturity, msg.sender);
        address unipool = uniFactory.createPool(zero, Adapter(adapter).underlying(), UNI_POOL_FEE); // deploy UNIV3 pool
        IUniswapV3Pool(unipool).initialize(sqrtPriceX96);
        poolManager.addSeries(adapter, maturity);
        emit SeriesSponsored(adapter, maturity, msg.sender);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Adapter via the AdapterFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address.
    /// @param target Target to onboard
    function onboardAdapter(address factory, address target) external returns (address adapterClone) {
        require(factories[factory], Errors.FactoryNotSupported);
        adapterClone = Factory(factory).deployAdapter(target);
        ERC20(target).approve(address(divider), type(uint256).max);
        ERC20(target).approve(address(adapterClone), type(uint256).max);
        poolManager.addTarget(target);
        emit AdapterOnboarded(adapterClone);
    }

    /// @notice Mint Zeros and Claims of a specific Series
    /// @dev backfill amount refers to the excess that has accrued since the first Claim from a Series was deposited
    /// @dev in next versions will be calculate here. Refer to GClaimManager.excess() for more details about this value.
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to deposit
    function swapTargetForZeros(
        address adapter, uint256 maturity, uint256 tBal, uint256 minAccepted
    ) external {
        (address zero, address claim, , , , , , ,) = divider.series(adapter, maturity);

        // transfer target directly to adapter for conversion
        ERC20(Adapter(adapter).getTarget()).safeTransferFrom(msg.sender, adapter, tBal);

        // convert target to underlying
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);

        // swap underlying for zeros
        uint256 zBal = _swap(Adapter(adapter).underlying(), zero, uBal, address(this), minAccepted); // TODO: swap on yieldspace not uniswap

        // transfer bought zeros to user
        ERC20(zero).safeTransfer(msg.sender, zBal);

    }

    function swapTargetForClaims(address adapter, uint256 maturity, uint256 tBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(adapter, maturity);
        ERC20 target = ERC20(Adapter(adapter).getTarget());

        // transfer target into this contract
        target.safeTransferFrom(msg.sender, address(this), tBal);

        // (1) Calculate target needed to borrow in order to issue and obtain the desired amount of claims
        // We get Zero/underlying price and we infer the Claim price (1 - zPrice).
        // We can then calculate how many claims we can get with the underlying uBal (uBal / Claim price) and
        // finally, we get the target we need to borrow by doing a unit conversion from Claim to Target using the last
        // scale value.
        uint256 targetToBorrow;
        { // block scope to avoid stack too deep error
            uint256 scale = Adapter(adapter).scale();
            uint256 tDecimals = target.decimals();
            uint256 tBase = 10**target.decimals();
            uint256 fee = (Adapter(adapter).getIssuanceFee() / convertBase(tDecimals));
            uint256 cPrice = 1*tBase - price(zero, Adapter(adapter).underlying());
            targetToBorrow = tBal.fdiv( ( 1*tBase - fee ).fmul(cPrice, tBase) + fee, tBase);

        }
        uint256 cBal = flashBorrow(abi.encode(Action.ZERO_TO_CLAIM), adapter, maturity, targetToBorrow);

        // transfer claims from issuance + issued claims from borrowed target (step 4) to msg.sender (if applicable)
        ERC20(claim).safeTransfer(msg.sender, cBal);
    }

    function swapZerosForTarget(address adapter, uint256 maturity, uint256 zBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(adapter, maturity);

        // transfer zeros into this contract
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal);

        // swap zeros for underlying
        uint256 uBal = _swap(zero, Adapter(adapter).underlying(), zBal, address(this), minAccepted); // TODO: swap on yieldspace pool

        // wrap underlying into target
        ERC20(Adapter(adapter).underlying()).safeTransfer(adapter, uBal);
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);

        // transfer target to msg.sender
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
    }

    function swapClaimsForTarget(address adapter, uint256 maturity, uint256 cBal, uint256 minAccepted) external {
        (address zero, address claim, , , , , , ,) = divider.series(adapter, maturity);
        uint256 lscale = divider.lscales(adapter, maturity, address(this));

        // transfer claims into this contract
        ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // (1) Calculate target needed to borrow in order to be able to buy as many Zeros as Claims passed
        // On one hand, I get the price of the underlying/zero from Yieldspace pool
        // On the other hand, I know that I would need to purchase `cBal/2` Zeros so as to end up with same amount of
        // Zeros and Claims and be able to combine them into target
        uint256 targetToBorrow;
        {
            uint256 rate = price(Adapter(adapter).underlying(), zero);
            ERC20 target = ERC20(Adapter(adapter).getTarget());
            uint256 tBase = 10**target.decimals();
            uint256 zBal = cBal.fdiv(2*tBase, tBase);
            uint256 uBal = zBal.fmul(rate, tBase);
            targetToBorrow = uBal.fmul(lscale, tBase); // amount of claims div 2 multiplied by rate gives me amount of underlying then multiplying by lscale gives me target
        }

        // (2) Flash borrow target
        uint256 tBal = flashBorrow(abi.encode(Action.CLAIM_TO_TARGET), adapter, maturity, targetToBorrow);

        // (6) Part of the target repays the loan, part is transferred to msg.sender
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
    }

    /* ========== VIEWS ========== */

    function price(address tokenA, address tokenB) public view returns (uint) {
        // return tokenA/tokenB TWAP
//        address pool = IUniswapV3Factory(uniFactory).getPool(tokenA, tokenB, UNI_POOL_FEE);
//        int24 timeWeightedAverageTick = OracleLibrary.consult(pool, TWAP_PERIOD);
//        uint128 baseUnit = uint128(10) ** uint128(ERC20(tokenA).decimals());
//        return OracleLibrary.getQuoteAtTick(timeWeightedAverageTick, baseUnit, tokenA, tokenB);
        // TODO: i'm commenting this here because I don't realise how to make it work with this but it should not be commented.
        return 0.95e18;
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
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param amount target amount to borrow
    /// @return claims issued with flashloan
    function flashBorrow(bytes memory data, address adapter, uint256 maturity, uint256 amount) internal returns (uint256) {
        ERC20 target = ERC20(Adapter(adapter).getTarget());
        uint256 _allowance = target.allowance(address(this), address(adapter));
        if (_allowance < amount) target.approve(address(adapter), type(uint256).max);
        (bool result, uint256 value) = Adapter(adapter).flashLoan(data, address(this), adapter, maturity, amount);
        require(result == true);
        return value;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(bytes calldata data, address initiator, address adapter, uint256 maturity, uint256 amount) external returns(bytes32, uint256) {
        require(msg.sender == address(adapter), Errors.FlashUntrustedBorrower);
        require(initiator == address(this), Errors.FlashUntrustedLoanInitiator);
        (address zero, , , , , , , ,) = divider.series(adapter, maturity);
        (Action action) = abi.decode(data, (Action));
        if (action == Action.ZERO_TO_CLAIM) {
            // (2) Issue
            uint256 issued = divider.issue(adapter, maturity, amount);

            // (3) Sell Zeros for underlying
            uint256 uBal = _swap(zero, Adapter(adapter).underlying(), issued, address(this), 0); // TODO: minAccepted

            // (4) Convert underlying into target
            ERC20(Adapter(adapter).underlying()).safeTransfer(adapter, uBal);
            Adapter(adapter).wrapUnderlying(uBal);
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), issued);
        } else if (action == Action.CLAIM_TO_TARGET) {
            // (3) Convert target into underlying (unwrap via protocol)
            uint256 uBal = Adapter(adapter).unwrapTarget(amount);

            // (4) Swap underlying for Zeros on Yieldspace pool
            uint256 zBal = _swap(Adapter(adapter).underlying(), zero, uBal, address(this), 0); // TODO: minAccepted

            // (5) Combine zeros and claim
            uint256 tBal = divider.combine(adapter, maturity, zBal);
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
        }
        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), 0);
    }

    function convertBase(uint256 decimals) internal returns (uint256) {
        uint256 base = 1;
        if (decimals != 18) {
            base = decimals > 18 ? 10 ** (decimals - 18) : 10 ** (18 - decimals);
        }
        return base;
    }

    /* ========== EVENTS ========== */
    event FactoryChanged(address indexed adapter, bool isOn);
    event SeriesSponsored(address indexed adapter, uint256 indexed maturity, address indexed sponsor);
    event AdapterOnboarded(address adapter);
}
