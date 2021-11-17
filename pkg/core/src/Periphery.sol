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

interface YieldSpacePoolLike {
    function onSwapGivenOut(
        bool _zeroIn,
        uint256 _amountOut,
        uint256 _reservesInAmount,
        uint256 _reservesOutAmount
    ) external view returns (uint256);
}

/// @title Periphery
contract Periphery is Trust {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;
    using Errors for string;

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
        ERC20(stake).safeTransferFrom(msg.sender, address(this), _convertToBase(stakeSize, stakeDecimals));

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
        ERC20(Adapter(adapter).getTarget()).safeTransferFrom(msg.sender, address(this), tBal); // pull target
        return _swapTargetForZeros(adapter, maturity, tBal, minAccepted);
    }

    /// @notice Swap Underlying to Zeros of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    function swapUnderlyingForZeros(
        address adapter,
        uint48 maturity,
        uint256 uBal,
        uint256 minAccepted
    ) external returns (uint256) {
        ERC20(Adapter(adapter).underlying()).safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal); // approve adapter to pull uBal
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // convert target to underlying
        return _swapTargetForZeros(adapter, maturity, tBal, minAccepted);
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
        ERC20(Adapter(adapter).getTarget()).safeTransferFrom(msg.sender, address(this), tBal);
        return _swapTargetForClaims(adapter, maturity, tBal);
    }

    /// @notice Swap Underlying to Claims of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    function swapUnderlyingForClaims(
        address adapter,
        uint48 maturity,
        uint256 uBal
    ) external returns (uint256) {
        ERC20(Adapter(adapter).underlying()).safeTransferFrom(msg.sender, address(this), uBal); // pull target
        ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal); // approve adapter to pull underlying
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        return _swapTargetForClaims(adapter, maturity, tBal);
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
        uint256 tBal = _swapZerosForTarget(adapter, maturity, zBal, minAccepted); // swap zeros for target
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal); // transfer target to msg.sender
        return tBal;
    }

    /// @notice Swap Zeros for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param zBal Balance of Zeros to sell
    /// @param minAccepted Min accepted amount of Target
    function swapZerosForUnderlying(
        address adapter,
        uint48 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) external returns (uint256) {
        uint256 tBal = _swapZerosForTarget(adapter, maturity, zBal, minAccepted); // swap zeros for target
        ERC20(Adapter(adapter).getTarget()).safeApprove(adapter, tBal); // approve adapter to pull target
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal); // unwrap target into underlying
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal); // transfer underlying to msg.sender
        return uBal;
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
        uint256 tBal = _swapClaimsForTarget(msg.sender, adapter, maturity, cBal);
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    /// @notice Swap Claims for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param cBal Balance of Claims to swap
    function swapClaimsForUnderlying(
        address adapter,
        uint48 maturity,
        uint256 cBal
    ) external returns (uint256) {
        uint256 tBal = _swapClaimsForTarget(msg.sender, adapter, maturity, cBal);
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal);
        return uBal;
    }

    /// @notice Adds liquidity providing target
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to provide
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
    function addLiquidityFromTarget(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint8 mode
    ) external {
        _addLiquidity(adapter, maturity, tBal, mode);
    }

    /// @notice Adds liquidity providing underlying
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to provide
    /// @param mode 0 = issues and sell Claims, 1 = issue and hold Claims
    function addLiquidityFromUnderlying(
        address adapter,
        uint48 maturity,
        uint256 uBal,
        uint8 mode
    ) external {
        // Wrap Underlying into Target
        ERC20(Adapter(adapter).underlying()).safeApprove(adapter, uBal);
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);
        _addLiquidity(adapter, maturity, tBal, mode);
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns target
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    function removeLiquidityToTarget(
        address adapter,
        uint48 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external {
        uint256 tBal = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal); // Send Target back to the User
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns underlying
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut lower limits for the tokens to receive (useful to account for slippage)
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping Zeros to underlying
    function removeLiquidityToUnderlying(
        address adapter,
        uint48 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) external {
        uint256 tBal = _removeLiquidity(adapter, maturity, lpBal, minAmountsOut, minAccepted);
        ERC20(Adapter(adapter).getTarget()).safeApprove(adapter, tBal);
        uint256 uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(msg.sender, uBal); // Send Underlying back to the User
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

    function _swapZerosForTarget(
        address adapter,
        uint48 maturity,
        uint256 zBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        ERC20(zero).safeTransferFrom(msg.sender, address(this), zBal); // pull zeros
        return _swap(zero, Adapter(adapter).getTarget(), zBal, poolIds[adapter][maturity], minAccepted); // swap zeros for underlying
    }

    function _swapTargetForZeros(
        address adapter,
        uint48 maturity,
        uint256 tBal,
        uint256 minAccepted
    ) internal returns (uint256) {
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        uint256 zBal = _swap(Adapter(adapter).getTarget(), zero, tBal, poolIds[adapter][maturity], minAccepted); // swap target for zeros
        ERC20(zero).safeTransfer(msg.sender, zBal); // transfer bought zeros to user
        return zBal;
    }

    function _swapTargetForClaims(
        address adapter,
        uint48 maturity,
        uint256 tBal
    ) internal returns (uint256) {
        (address zero, address claim, , , , , , , ) = divider.series(adapter, maturity);

        // issue zeros and claims & swap zeros for target
        uint256 issued = divider.issue(adapter, maturity, tBal);
        tBal = _swap(zero, Adapter(adapter).getTarget(), issued, poolIds[adapter][maturity], 0);

        // transfer claims & target to user
        ERC20(Adapter(adapter).getTarget()).safeTransfer(msg.sender, tBal);
        ERC20(claim).safeTransfer(msg.sender, issued);
        return issued;
    }

    function _swapClaimsForTarget(
        address sender,
        address adapter,
        uint48 maturity,
        uint256 cBal
    ) internal returns (uint256) {
        (, address claim, , , , , , , ) = divider.series(adapter, maturity);

        // transfer claims into this contract if needed
        if (sender != address(this)) ERC20(claim).safeTransferFrom(msg.sender, address(this), cBal);

        // calculate target to borrow by calling AMM
        bytes32 poolId = poolIds[adapter][maturity];
        (address pool, ) = balancerVault.getPool(poolId);
        (, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolId);
        uint256 targetToBorrow = YieldSpacePoolLike(pool).onSwapGivenOut(false, cBal, balances[0], balances[1]);

        // flash borrow target (following actions in `onFlashLoan`)
        return _flashBorrow(abi.encode(), adapter, maturity, targetToBorrow);
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

        // (1) Based on zeros:target ratio from current pool reserves and tBal passed
        // calculate amount of tBal needed so as to issue Zeros that would keep the ratio
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolIds[adapter][maturity]);
        uint256 zBalInTarget = (balances[1] * tBal) / (balances[1] + balances[0]);

        // (2) Issue Zeros & Claim
        uint256 issued = divider.issue(adapter, maturity, zBalInTarget);

        // (3) Target to provide | tBal - zBalInTarget |
        uint256 tBalToPovide = tBal > zBalInTarget ? tBal - zBalInTarget : zBalInTarget - tBal;

        // (4) Add liquidity to Space & send the LP Shares to recipient
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = tBalToPovide;
        amounts[1] = issued;

        _addLiquidityToSpace(poolIds[adapter][maturity], tokens, amounts);

        {
            // Send any leftover underlying or zeros back to the user
            uint256 tBal = target.balanceOf(address(this));
            uint256 zBal = ERC20(zero).balanceOf(address(this));
            if (tBal > 0) target.safeTransfer(msg.sender, tBal);
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

    function _removeLiquidity(
        address adapter,
        uint48 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted
    ) internal returns (uint256) {
        address target = Adapter(adapter).getTarget();
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);
        bytes32 poolId = poolIds[adapter][maturity];
        (address pool, ) = balancerVault.getPool(poolId);

        // (0) Pull LP tokens from sender
        ERC20(pool).safeTransferFrom(msg.sender, address(this), lpBal);

        // (1) Remove liquidity from Space
        (uint256 tBal, uint256 zBal) = _removeLiquidityFromSpace(poolId, zero, target, minAmountsOut, lpBal);

        if (block.timestamp >= maturity) {
            // (2) Redeem Zeros for Target
            tBal += divider.redeemZero(adapter, maturity, zBal);
        } else {
            // (2) Sell Zeros for Target
            tBal += _swap(zero, target, zBal, poolId, minAccepted);
        }

        return tBal;
    }

    /// @notice Initiate a flash loan
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param amount target amount to borrow
    /// @return claims issued with flashloan
    function _flashBorrow(
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
        bytes calldata,
        address initiator,
        address adapter,
        uint48 maturity,
        uint256 amount
    ) external returns (bytes32, uint256) {
        require(msg.sender == address(adapter), Errors.FlashUntrustedBorrower);
        require(initiator == address(this), Errors.FlashUntrustedLoanInitiator);
        (address zero, , , , , , , , ) = divider.series(adapter, maturity);

        // swap Target for Zeros
        uint256 zBal = _swap(Adapter(adapter).getTarget(), zero, amount, poolIds[adapter][maturity], 0); // TODO: minAccepted

        // combine zeros and claim
        uint256 tBal = divider.combine(adapter, maturity, zBal);
        return (keccak256("ERC3156FlashBorrower.onFlashLoan"), tBal - amount);
    }

    function _addLiquidityToSpace(
        bytes32 poolId,
        ERC20[] memory tokens,
        uint256[] memory amounts
    ) internal {
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
        address target,
        uint256[] memory minAmountsOut,
        uint256 lpBal
    ) internal returns (uint256, uint256) {
        uint256 tBalBefore = ERC20(target).balanceOf(address(this));
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
        uint256 tBalAfter = ERC20(target).balanceOf(address(this));
        return (tBalAfter - tBalBefore, zBalAfter - zBalBefore);
    }

    /* ========== HELPER FUNCTIONS ========== */

    function _convertToBase(uint256 amount, uint256 decimals) internal pure returns (uint256) {
        if (decimals != 18) {
            amount = decimals > 18 ? amount * 10**(decimals - 18) : amount / 10**(18 - decimals);
        }
        return amount;
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
