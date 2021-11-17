// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { SafeERC20, ERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { FixedMath } from "./external/FixedMath.sol";
import { BalancerVault, IAsset } from "./external/balancer/Vault.sol";
import { BalancerPool } from "./external/balancer/Pool.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { CropAdapter as Adapter } from "./adapters/CropAdapter.sol";
import { BaseFactory as Factory } from "./adapters/BaseFactory.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "@sense-finance/v1-fuse/src/PoolManager.sol";
import { Token } from "./tokens/Token.sol";

interface YieldSpaceFactoryLike {
    function create(
        address,
        address,
        uint256
    ) external returns (address);
}

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;
    using Errors for string;

    enum Action {
        ZERO_TO_CLAIM,
        CLAIM_TO_TARGET
    }

    /// @notice Configuration
    uint24 public constant UNI_POOL_FEE = 10000; // denominated in hundredths of a bip
    uint32 public constant TWAP_PERIOD = 10 minutes; // ideal TWAP interval.

    /// @notice Program state
    Divider public immutable divider;
    PoolManager public immutable poolManager;
    YieldSpaceFactoryLike public immutable yieldSpaceFactory;
    BalancerVault public immutable balancerVault;

    mapping(address => mapping(uint256 => bytes32)) poolIds;
    mapping(address => bool) public factories; // adapter factories -> is supported

    constructor(
        address _divider,
        address _poolManager,
        address _ysFactory,
        address _balancerVault
    ) Trust(msg.sender) {
        divider = Divider(_divider);
        poolManager = PoolManager(_poolManager);
        yieldSpaceFactory = YieldSpaceFactoryLike(_ysFactory);
        balancerVault = BalancerVault(_balancerVault);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Sponsor a new Series
    /// @dev Calls divider to initalise a new series
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    function sponsorSeries(address adapter, uint48 maturity) external returns (address zero, address claim) {
        (, , , , address stake, uint256 stakeSize, , , ) = Adapter(adapter).adapterParams();

        // transfer stakeSize from sponsor into this contract
        uint256 stakeDecimals = ERC20(stake).decimals();
        ERC20(stake).safeTransferFrom(msg.sender, address(this), stakeSize / convertBase(stakeDecimals));

        // approve divider to withdraw stake assets
        ERC20(stake).safeApprove(address(divider), type(uint256).max);

        (zero, claim) = divider.initSeries(adapter, maturity, msg.sender);

        address pool = yieldSpaceFactory.create(address(divider), adapter, uint256(maturity));
        poolIds[adapter][maturity] = BalancerPool(pool).getPoolId();
        poolManager.queueSeries(adapter, maturity, pool);
        emit SeriesSponsored(adapter, maturity, msg.sender);
    }

    /// @notice Onboards a target
    /// @dev Deploys a new Adapter via the AdapterFactory
    /// @dev Onboards Target onto Fuse. Caller must know the factory address
    /// @param target Target to onboard
    function onboardAdapter(address factory, address target) external returns (address adapterClone) {
        require(factories[factory], Errors.FactoryNotSupported);
        adapterClone = Factory(factory).deployAdapter(target);
        ERC20(target).safeApprove(address(divider), type(uint256).max);
        ERC20(target).safeApprove(address(adapterClone), type(uint256).max);
        poolManager.addTarget(target, adapterClone);
        emit AdapterOnboarded(adapterClone);
    }

    /// @notice Swap Target to Zeros of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    function swapTargetForZeros(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) external returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);

        // transfer target to periphery
        ERC20(Adapter(adapter).getTarget()).safeTransferFrom(msg.sender, address(this), tBal);

        // approve adapter to pull tBal
        ERC20(Adapter(adapter).getTarget()).safeApprove(adapter, tBal);

        // convert target to underlying
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);

        // swap underlying for zeros
        uint256 zBal = _swap(Adapter(adapter).underlying(), zero, uBal, poolIds[adapter][maturity], minAccepted); // TODO: swap on yieldspace not uniswap

        // transfer bought zeros to user
        ERC20(zero).safeTransfer(msg.sender, zBal);
        return zBal;
    }

    /// @notice Swap Target to Claims of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    function swapTargetForClaims(
        address adapter,
        uint48 maturity,
        uint256 tBal
    ) external returns (uint256) {
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);
        ERC20 target = ERC20(Adapter(adapter).getTarget());

        // transfer target into this contract
        target.safeTransferFrom(msg.sender, address(this), tBal);

        // (1) Calculate target needed to borrow in order to issue and obtain the desired amount of claims
        // We get Zero/underlying price and we infer the Claim price (1 - zPrice).
        // We can then calculate how many claims we can get with the underlying uBal (uBal / Claim price) and
        // finally, we get the target we need to borrow by doing a unit conversion from Claim to Target using the last
        // scale value.
        uint256 targetToBorrow;
        {
            uint256 tDecimals = target.decimals();
            uint256 tBase = 10**target.decimals();
            uint256 fee = (Adapter(adapter).getIssuanceFee() / convertBase(tDecimals));
            uint256 cPrice = tBase - price(zero, Adapter(adapter).underlying());
            targetToBorrow = tBal.fdiv((tBase - fee).fmul(cPrice, tBase) + fee, tBase);
        }
        uint256 cBal = flashBorrow(abi.encode(Action.ZERO_TO_CLAIM), adapter, maturity, targetToBorrow);

        // transfer claims from issuance + issued claims from borrowed target (step 4) to msg.sender (if applicable)
        ERC20(claim).safeTransfer(msg.sender, cBal);
        return cBal;
    }

    /// @notice Swap Zeros for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Zeros to sell
    /// @param minAccepted Min accepted amount of Target
    function swapZerosForTarget(
        address adapter,
        uint48 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);

        // transfer zeros into this contract
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal);

        // swap zeros for underlying
        uint256 uBal = _swap(zero, Adapter(adapter).underlying(), zBal, poolIds[adapter][maturity], minAccepted);

        // approve adapter to pull underlying
        ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal);
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);

        // transfer target to msg.sender
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    /// @notice Swap Claims for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Claims to swap
    function swapClaimsForTarget(
        address adapter,
        uint48 maturity,
        uint256 cBal
    ) external returns (uint256) {
        return _swapClaimsForTarget(msg.sender, adapter, maturity, cBal);
    }

    function _swapClaimsForTarget(
        address sender,
        address adapter,
        uint48 maturity,
        uint256 cBal
    ) internal returns (uint256) {
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);
        uint256 lscale = divider.lscales(adapter, maturity, sender);

        // transfer claims into this contract if needed
        if (sender != address(this)) ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // (1) Calculate target needed to borrow in order to be able to buy as many Zeros as Claims passed
        // On one hand, I get the price of the underlying/zero from Yieldspace pool
        // On the other hand, I know that I would need to purchase `cBal/2` Zeros so as to end up with same amount of
        // Zeros and Claims and be able to combine them into target
        uint256 targetToBorrow;
        {
            uint256 rate = price(Adapter(adapter).underlying(), zero);
            ERC20 target = ERC20(Adapter(adapter).getTarget());
            uint256 tBase = 10**target.decimals();
            uint256 zBal = cBal.fdiv(2 * tBase, tBase);
            uint256 uBal = zBal.fmul(rate, tBase);
            targetToBorrow = uBal.fmul(lscale, tBase); // amount of claims div 2 multiplied by rate gives me amount of underlying then multiplying by lscale gives me target
        }

        // (2) Flash borrow target
        uint256 tBal = flashBorrow(abi.encode(Action.CLAIM_TO_TARGET), adapter, maturity, targetToBorrow);

        // (6) Part of the target repays the loan, part is transferred to msg.sender if needed
        if (sender != address(this)) ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    /// @notice Adds liquidity providing target
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to provide
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
    function addLiquidity(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint8 mode
    ) external {
        _addLiquidity(adapter, maturity, tBal, mode);
    }

    function _addLiquidity(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint8 mode
    ) internal {
        ERC20 target = ERC20(Adapter(adapter).getTarget());
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);

        // (0) Pull target from sender
        target.safeTransferFrom(msg.sender, address(this), tBal);

        // (1) Based on zeros:underlying ratio from current pool reserves and tBal passed
        // calculate amount of tBal needed so as to issue Zeros that would keep the ratio
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolIds[adapter][maturity]);
        uint256 zBalInTarget = (balances[1] * tBal) / (balances[1] + balances[0]);

        // (2) Issue Zeros & Claim
        uint256 issued = divider.issue(adapter, maturity, zBalInTarget);

        // (3) Convert remaining target into underlying (unwrap via protocol)
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal > zBalInTarget ? tBal - zBalInTarget : zBalInTarget - tBal);

        // (4) Add liquidity to Space & send the LP Shares to recipient
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uBal;
        amounts[1] = issued;

        _addLiquidityToSpace(poolIds[adapter][maturity], tokens, amounts);

        {
            // Send any leftover underlying or zeros back to the user
            ERC20 underlying = ERC20(Adapter(adapter).underlying());
            uint256 uBal = underlying.balanceOf(address(this));
            uint256 zBal = ERC20(zero).balanceOf(address(this));
            if (uBal > 0) underlying.safeTransfer(msg.sender, uBal);
            if (zBal > 0) ERC20(zero).safeTransfer(msg.sender, zBal);
        }

        if (mode == 0) {
            // (5) Sell claims
            uint256 tAmount = _swapClaimsForTarget(address(this), adapter, maturity, issued);
            // (6) Send remaining Target back to the User
            target.safeTransfer(msg.sender, tAmount);
        } else {
            // (5) Send Claims back to the User
            ERC20(claim).safeTransfer(msg.sender, issued);
        }
    }

    /// @notice Removes liquidity providing an amount of LP tokens
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    function removeLiquidity(
        address adapter,
        uint48 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external {
        uint256 tBal = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        // Send Target back to the User
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
    }

    function _removeLiquidity(
        address adapter,
        uint48 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) internal returns (uint256) {
        address underlying = Adapter(adapter).underlying();
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        bytes32 poolId = poolIds[adapter][maturity];
        (address pool, ) = balancerVault.getPool(poolId);

        // (0) Pull LP tokens from sender
        ERC20(pool).safeTransferFrom(msg.sender, address(this), lpBal);

        // (1) Remove liquidity from Space
        (uint256 uBal, uint256 zBal) = _removeLiquidityFromSpace(poolId, zero, underlying, minAmountsOut, lpBal);

        uint256 tBal;
        if (block.timestamp >= maturity) {
            // (2) Redeem Zeros for Target
            tBal += divider.redeemZero(adapter, maturity, zBal);
        } else {
            // (2) Sell Zeros for Underlying
            uBal += _swap(zero, underlying, zBal, poolId, minAccepted);
        }

        // (3) Wrap Underlying into Target
        ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal);
        tBal += Adapter(adapter).wrapUnderlying(uBal);
        return tBal;
    }

    /// @notice Migrates liquidity position from one series to another
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param srcAdapter Adapter address for the source Series
    /// @param dstAdapter Adapter address for the destination Series
    /// @param srcMaturity Maturity date for the source Series
    /// @param dstMaturity Maturity date for the destination Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
    function migrateLiquidity(
        address srcAdapter,
        address dstAdapter,
        uint48 srcMaturity,
        uint48 dstMaturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        uint8 mode
    ) external {
        uint256 tBal = _removeLiquidity(srcAdapter, srcMaturity, lpBal, minAmountsOut, minAccepted);
        _addLiquidity(dstAdapter, dstMaturity, tBal, mode);
    }

    /* ========== VIEWS ========== */

    function price(address tokenA, address tokenB) public view returns (uint256) {
        // TODO: unimplemented – solve this with the yield space for the optimal swap
        return 0.95e18;
    }

    function _swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 poolId,
        uint256 minAccepted
    ) internal returns (uint256 amountOut) {
        // approve vault to spend tokenIn
        ERC20(assetIn).safeApprove(address(balancerVault), amountIn);

        BalancerVault.SingleSwap memory request = BalancerVault.SingleSwap({
            poolId: poolId,
            kind: BalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amountIn,
            userData: "0x" // TODO: are we sure about this?
        });

        BalancerVault.FundManagement memory funds = BalancerVault.FundManagement({
            sender: msg.sender,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        amountOut = balancerVault.swap(request, funds, minAccepted, type(uint256).max);
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

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Initiate a flash loan
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param amount target amount to borrow
    /// @return claims issued with flashloan
    function flashBorrow(
        bytes memory data,
        address adapter,
        uint48 maturity,
        uint256 amount
    ) internal returns (uint256) {
        ERC20 target = ERC20(Adapter(adapter).getTarget());
        uint256 _allowance = target.allowance(address(this), address(adapter));
        if (_allowance < amount) target.safeApprove(address(adapter), type(uint256).max);
        (bool result, uint256 value) = Adapter(adapter).flashLoan(data, address(this), adapter, maturity, amount);
        require(result == true);
        return value;
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        bytes calldata data,
        address initiator,
        address adapter,
        uint48 maturity,
        uint256 amount
    ) external returns (bytes32, uint256) {
        require(msg.sender == address(adapter), Errors.FlashUntrustedBorrower);
        require(initiator == address(this), Errors.FlashUntrustedLoanInitiator);
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        Action action = abi.decode(data, (Action));
        if (action == Action.ZERO_TO_CLAIM) {
            // (2) Issue
            uint256 issued = divider.issue(adapter, maturity, amount);

            // (3) Sell Zeros for underlying
            uint256 uBal = _swap(zero, Adapter(adapter).underlying(), issued, poolIds[adapter][maturity], 0); // TODO: minAccepted

            // (4) Convert underlying into target
            ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal);
            Adapter(adapter).wrapUnderlying(uBal);
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), issued);
        } else if (action == Action.CLAIM_TO_TARGET) {
            // (3) Convert target into underlying (unwrap via protocol)
            uint256 uBal = Adapter(adapter).unwrapTarget(amount);

            // (4) Swap underlying for Zeros on Yieldspace pool
            uint256 zBal = _swap(Adapter(adapter).underlying(), zero, uBal, poolIds[adapter][maturity], 0); // TODO: minAccepted

            // (5) Combine zeros and claim
            uint256 tBal = divider.combine(adapter, maturity, zBal);
            return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
        }
        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), 0);
    }

    function _addLiquidityToSpace(
        bytes32 poolId,
        ERC20[] memory tokens,
        uint256[] memory amounts
    ) internal {
        // (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory assets = _convertERC20sToAssets(tokens);
        for (uint8 i; i < tokens.length; i++) {
            // tokens and amounts must be in same order
            tokens[i].safeApprove(address(balancerVault), amounts[i]);
        }
        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: amounts,
            userData: abi.encode(1, amounts), // EXACT_TOKENS_IN_FOR_BPT_OUT = 1, user sends precise quantities of tokens, and receives an estimated but unknown (computed at run time) quantity of BPT. (more info here https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-joins.md)
            fromInternalBalance: false
        });
        balancerVault.joinPool(poolId, address(this), msg.sender, request);
    }

    function _removeLiquidityFromSpace(
        bytes32 poolId,
        address zero,
        address underlying,
        uint256[] memory minAmountsOut,
        uint256 lpBal
    ) internal returns (uint256, uint256) {
        uint256 uBalBefore = ERC20(underlying).balanceOf(address(this));
        uint256 zBalBefore = ERC20(zero).balanceOf(address(this));

        // ExitPoolRequest params
        (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory assets = _convertERC20sToAssets(tokens);
        BalancerVault.ExitPoolRequest memory request = BalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(1, lpBal),
            toInternalBalance: false
        });
        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);

        uint256 zBalAfter = ERC20(zero).balanceOf(address(this));
        uint256 uBalAfter = ERC20(underlying).balanceOf(address(this));
        return (uBalAfter - uBalBefore, zBalAfter - zBalBefore);
    }

    /* ========== HELPER FUNCTIONS ========== */

    function convertBase(uint256 decimals) internal returns (uint256) {
        uint256 base = 1;
        if (decimals != 18) {
            base = decimals > 18 ? 10**(decimals - 18) : 10**(18 - decimals);
        }
        return base;
    }

    // @author https://github.com/balancer-labs/balancer-examples/blob/master/packages/liquidity-provision/contracts/LiquidityProvider.sol#L33
    // @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }

    /* ========== EVENTS ========== */
    event FactoryChanged(address indexed adapter, bool isOn);
    event SeriesSponsored(address indexed adapter, uint256 indexed maturity, address indexed sponsor);
    event AdapterOnboarded(address adapter);
}
