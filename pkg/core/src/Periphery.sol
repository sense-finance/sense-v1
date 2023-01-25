// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedMath } from "./external/FixedMath.sol";
import { BalancerVault, IAsset } from "./external/balancer/Vault.sol";
import { BalancerPool } from "./external/balancer/Pool.sol";
import { IERC3156FlashBorrower } from "./external/flashloan/IERC3156FlashBorrower.sol";
import { IPermit2 } from "@sense-finance/v1-core/external/IPermit2.sol";

// Internal references
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";
import { Levels } from "@sense-finance/v1-utils/libs/Levels.sol";
import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { BaseAdapter as Adapter } from "./adapters/abstract/BaseAdapter.sol";
import { BaseFactory as AdapterFactory } from "./adapters/abstract/factories/BaseFactory.sol";
import { Divider } from "./Divider.sol";
import { PoolManager } from "@sense-finance/v1-fuse/PoolManager.sol";

interface SpaceFactoryLike {
    function create(address, uint256) external returns (address);

    function pools(address adapter, uint256 maturity) external view returns (address);
}

/// @title Periphery
contract Periphery is Trust, IERC3156FlashBorrower {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;
    using Levels for uint256;

    /* ========== PUBLIC CONSTANTS ========== */

    /// @notice Lower bound on the amount of Claim tokens one can swap in for Target
    uint256 public constant MIN_YT_SWAP_IN = 0.000001e18;

    /// @notice Acceptable error when estimating the tokens resulting from a specific swap
    uint256 public constant PRICE_ESTIMATE_ACCEPTABLE_ERROR = 0.00000001e18;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    Divider public immutable divider;

    /// @notice Sense core Divider address
    BalancerVault public immutable balancerVault;

    /// @notice Permit2 contract
    IPermit2 public immutable permit2;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

    /// @notice Sense core Divider address
    PoolManager public poolManager;

    /// @notice Sense core Divider address
    SpaceFactoryLike public spaceFactory;

    /// @notice adapter factories -> is supported
    mapping(address => bool) public factories;

    /// @notice adapter -> bool
    mapping(address => bool) public verified;

    /* ========== DATA STRUCTURES ========== */

    struct PoolLiquidity {
        ERC20[] tokens;
        uint256[] amounts;
        uint256 minBptOut;
    }

    constructor(
        address _divider,
        address _poolManager,
        address _spaceFactory,
        address _balancerVault,
        address _permit2
    ) Trust(msg.sender) {
        divider = Divider(_divider);
        poolManager = PoolManager(_poolManager);
        spaceFactory = SpaceFactoryLike(_spaceFactory);
        balancerVault = BalancerVault(_balancerVault);
        permit2 = IPermit2(_permit2);
    }

    /* ========== SERIES / ADAPTER MANAGEMENT ========== */

    /// @notice Sponsor a new Series in any adapter previously onboarded onto the Divider
    /// @dev Called by an external address, initializes a new series in the Divider
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    /// @param withPool Whether to deploy a Space pool or not (only works for unverified adapters)
    function sponsorSeries(
        address adapter,
        uint256 maturity,
        bool withPool,
        bytes memory permit
    ) external returns (address pt, address yt) {
        (, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();

        // Transfer stakeSize from sponsor into this contract
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg, // permit message.
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: stakeSize }), // transfer recipient and amount.
            msg.sender, // owner of the tokens
            signature // packed signature that was the result of signing the EIP712 hash of `permit`.
        );

        // Approve divider to withdraw stake assets
        ERC20(stake).safeApprove(address(divider), stakeSize);

        (pt, yt) = divider.initSeries(adapter, maturity, msg.sender);

        // Space pool is always created for verified adapters whilst is optional for unverified ones.
        // Automatically queueing series is only for verified adapters
        if (verified[adapter]) {
            if (address(poolManager) == address(0)) {
                spaceFactory.create(adapter, maturity);
            } else {
                poolManager.queueSeries(adapter, maturity, spaceFactory.create(adapter, maturity));
            }
        } else {
            if (withPool) {
                spaceFactory.create(adapter, maturity);
            }
        }
        emit SeriesSponsored(adapter, maturity, msg.sender);
    }

    /// @notice Deploy and onboard a Adapter
    /// @dev Called by external address, deploy a new Adapter via an Adapter Factory
    /// @param f Factory to use
    /// @param target Target to onboard
    /// @param data Additional encoded data needed to deploy the adapter
    function deployAdapter(
        address f,
        address target,
        bytes memory data
    ) external returns (address adapter) {
        if (!factories[f]) revert Errors.FactoryNotSupported();
        adapter = AdapterFactory(f).deployAdapter(target, data);
        emit AdapterDeployed(adapter);
        _verifyAdapter(adapter, true);
        _onboardAdapter(adapter, true);
    }

    /* ========== LIQUIDITY UTILS ========== */

    /// @notice Swap Target to PTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to sell
    /// @param minAccepted Min accepted amount of PT
    /// @param receiver Address to receive the PT
    /// @return ptBal amount of PT received
    function swapTargetForPTs(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted,
        address receiver,
        bytes memory permit
    ) external returns (uint256 ptBal) {
        // pull underlying
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: tBal }),
            msg.sender,
            signature
        );
        return _swapTargetForPTs(adapter, maturity, tBal, minAccepted, receiver);
    }

    /// @notice Swap Underlying to PTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to sell
    /// @param minAccepted Min accepted amount of PT
    /// @param receiver Address to receive the PT
    /// @return ptBal amount of PT received
    function swapUnderlyingForPTs(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint256 minAccepted,
        address receiver,
        bytes memory permit
    ) external returns (uint256 ptBal) {
        // pull underlying
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal }),
            msg.sender,
            signature
        );
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal); // wrap underlying into target
        ptBal = _swapTargetForPTs(adapter, maturity, tBal, minAccepted, receiver);
    }

    /// @notice Swap Target to YTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param targetIn Balance of Target to sell
    /// @param targetToBorrow Balance of Target to borrow
    /// @param minOut Min accepted amount of YT
    /// @param receiver Address to receive the YT
    /// @return targetBal amount of Target sent back
    /// @return ytBal amount of YT received
    function swapTargetForYTs(
        address adapter,
        uint256 maturity,
        uint256 targetIn,
        uint256 targetToBorrow,
        uint256 minOut,
        address receiver,
        bytes memory permit
    ) external returns (uint256 targetBal, uint256 ytBal) {
        // pull target
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: targetIn }),
            msg.sender,
            signature
        );
        (targetBal, ytBal) = _flashBorrowAndSwapToYTs(adapter, maturity, targetIn, targetToBorrow, minOut);
        ERC20(Adapter(adapter).target()).safeTransfer(receiver, targetBal);
        ERC20(divider.yt(adapter, maturity)).safeTransfer(receiver, ytBal);
    }

    /// @notice Swap Underlying to Yield of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param underlyingIn Balance of Underlying to sell
    /// @param targetToBorrow Balance of Target to borrow
    /// @param minOut Min accepted amount of YT
    /// @param receiver Address to receive the YT
    /// @return targetBal amount of Target sent back
    /// @return ytBal amount of YT received
    function swapUnderlyingForYTs(
        address adapter,
        uint256 maturity,
        uint256 underlyingIn,
        uint256 targetToBorrow,
        uint256 minOut,
        address receiver,
        bytes memory permit
    ) external returns (uint256 targetBal, uint256 ytBal) {
        // pull underlying
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: underlyingIn }),
            msg.sender,
            signature
        );
        // Wrap Underlying into Target and swap it for YTs
        {
            uint256 targetIn = Adapter(adapter).wrapUnderlying(underlyingIn);
            (targetBal, ytBal) = _flashBorrowAndSwapToYTs(adapter, maturity, targetIn, targetToBorrow, minOut);
        }

        ERC20(Adapter(adapter).target()).safeTransfer(receiver, targetBal);
        ERC20(divider.yt(adapter, maturity)).safeTransfer(receiver, ytBal);
    }

    /// @notice Swap PTs for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param ptBal Balance of PT to sell
    /// @param minAccepted Min accepted amount of Target
    /// @param receiver Address to receive the Target
    /// @return tBal amount of Target received
    function swapPTsForTarget(
        address adapter,
        uint256 maturity,
        uint256 ptBal,
        uint256 minAccepted,
        address receiver,
        bytes memory permit
    ) external returns (uint256 tBal) {
        tBal = _swapPTsForTarget(adapter, maturity, ptBal, minAccepted, permit); // swap PTs for target
        ERC20(Adapter(adapter).target()).safeTransfer(receiver, tBal); // transfer target to receiver
    }

    /// @notice Swap PTs for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param ptBal Balance of PT to sell
    /// @param minAccepted Min accepted amount of Target
    /// @param receiver Address to receive the Underlying
    /// @return uBal amount of Underlying received
    function swapPTsForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 ptBal,
        uint256 minAccepted,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal) {
        uint256 tBal = _swapPTsForTarget(adapter, maturity, ptBal, minAccepted, permit); // swap PTs for target
        uBal = Adapter(adapter).unwrapTarget(tBal); // unwrap target into underlying
        ERC20(Adapter(adapter).underlying()).safeTransfer(receiver, uBal); // transfer underlying to receiver
    }

    /// @notice Swap YT for Target of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param ytBal Balance of YTs to swap
    /// @param receiver Address to receive the Target
    /// @return tBal amount of Target received
    function swapYTsForTarget(
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        address receiver,
        bytes memory permit
    ) external returns (uint256 tBal) {
        tBal = _swapYTsForTarget(msg.sender, adapter, maturity, ytBal, permit);
        ERC20(Adapter(adapter).target()).safeTransfer(receiver, tBal);
    }

    /// @notice Swap YT for Underlying of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param ytBal Balance of YTs to swap
    /// @param receiver Address to receive the Underlying
    /// @return uBal amount of Underlying received
    function swapYTsForUnderlying(
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal) {
        uint256 tBal = _swapYTsForTarget(msg.sender, adapter, maturity, ytBal, permit);
        uBal = Adapter(adapter).unwrapTarget(tBal);
        ERC20(Adapter(adapter).underlying()).safeTransfer(receiver, uBal);
    }

    /// @notice Adds liquidity providing target
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param tBal Balance of Target to provide
    /// @param mode 0 = issues and sell YT, 1 = issue and hold YT
    /// @param minBptOut Minimum BPT the user will accept out for this transaction
    /// @param receiver Address to receive the BPT
    /// @dev see return description of _addLiquidity
    function addLiquidityFromTarget(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint8 mode,
        uint256 minBptOut,
        address receiver,
        bytes memory permit
    )
        external
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        // pull target
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: tBal }),
            msg.sender,
            signature
        );
        (tAmount, issued, lpShares) = _addLiquidity(adapter, maturity, tBal, mode, minBptOut, receiver, permit);
    }

    /// @notice Adds liquidity providing underlying
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Balance of Underlying to provide
    /// @param mode 0 = issues and sell YT, 1 = issue and hold YT
    /// @param minBptOut Minimum BPT the user will accept out for this transaction
    /// @param receiver Address to receive the BPT
    /// @dev see return description of _addLiquidity
    function addLiquidityFromUnderlying(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        uint8 mode,
        uint256 minBptOut,
        address receiver,
        bytes memory permit
    )
        external
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        // pull underlying
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal }),
            msg.sender,
            signature
        );
        // Wrap Underlying into Target
        uint256 tBal = Adapter(adapter).wrapUnderlying(uBal);
        (tAmount, issued, lpShares) = _addLiquidity(adapter, maturity, tBal, mode, minBptOut, receiver, permit);
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns target
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut minimum accepted amounts of PTs and Target given the amount of LP shares provided
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping PTs to underlying
    /// @param intoTarget if true, it will try to swap PTs into Target. Will revert if there's not enough liquidity to perform the swap.
    /// @param receiver Address to receive the Target
    /// @return tBal amount of target received and ptBal amount of PTs (in case it's called after maturity and redeem is restricted)
    function removeLiquidity(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        bool intoTarget,
        address receiver,
        bytes memory permit
    ) external returns (uint256 tBal, uint256 ptBal) {
        (tBal, ptBal) = _removeLiquidity(
            adapter,
            maturity,
            lpBal,
            minAmountsOut,
            minAccepted,
            intoTarget,
            receiver,
            permit
        );
        ERC20(Adapter(adapter).target()).safeTransfer(receiver, tBal); // Send Target to the receiver
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns underlying
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut minimum accepted amounts of PTs and Target given the amount of LP shares provided
    /// @param minAccepted only used when removing liquidity on/after maturity and its the min accepted when swapping PTs to underlying
    /// @param intoTarget if true, it will try to swap PTs into Target. Will revert if there's not enough liquidity to perform the swap.
    /// @param receiver Address to receive the Underlying
    /// @return uBal amount of underlying received and ptBal PTs (in case it's called after maturity and redeem is restricted or intoTarget is false)
    function removeLiquidityAndUnwrapTarget(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        bool intoTarget,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal, uint256 ptBal) {
        uint256 tBal;
        (tBal, ptBal) = _removeLiquidity(
            adapter,
            maturity,
            lpBal,
            minAmountsOut,
            minAccepted,
            intoTarget,
            receiver,
            permit
        );
        ERC20(Adapter(adapter).underlying()).safeTransfer(receiver, uBal = Adapter(adapter).unwrapTarget(tBal)); // Send Underlying to the receiver
    }

    /// @notice Migrates liquidity position from one series to another
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param srcAdapter Adapter address for the source Series
    /// @param dstAdapter Adapter address for the destination Series
    /// @param srcMaturity Maturity date for the source Series
    /// @param dstMaturity Maturity date for the destination Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param minAmountsOut Minimum accepted amounts of PTs and Target given the amount of LP shares provided
    /// @param minAccepted Min accepted amount of target when swapping PTs (only used when removing liquidity on/after maturity)
    /// @param mode 0 = issues and sell YT, 1 = issue and hold YT
    /// @param intoTarget if true, it will try to swap PTs into Target. Will revert if there's not enough liquidity to perform the swap
    /// @param minBptOut Minimum BPT the user will accept out for this transaction
    /// @dev see return description of _addLiquidity. It also returns amount of PTs (in case it's called after maturity and redeem is restricted or inttoTarget is false)
    function migrateLiquidity(
        address srcAdapter,
        address dstAdapter,
        uint256 srcMaturity,
        uint256 dstMaturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        uint8 mode,
        bool intoTarget,
        uint256 minBptOut,
        bytes memory permit
    )
        external
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares,
            uint256 ptBal
        )
    {
        if (Adapter(srcAdapter).target() != Adapter(dstAdapter).target()) revert Errors.TargetMismatch();
        {
            (, ptBal) = _removeLiquidity(
                srcAdapter,
                srcMaturity,
                lpBal,
                minAmountsOut,
                minAccepted,
                intoTarget,
                msg.sender,
                permit
            );
            ERC20 target = ERC20(Adapter(srcAdapter).target());
            (tAmount, issued, lpShares) = _addLiquidity(
                dstAdapter,
                dstMaturity,
                target.balanceOf(address(this)),
                mode,
                minBptOut,
                msg.sender,
                permit
            );
        }
    }

    /* ========== UTILS ========== */

    /// @notice Mint PTs & YTs of a specific Series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series [unix time]
    /// @param targetIn Amount of Target to issue with
    /// @dev The balance of PTs and YTs minted will be the same value in units of underlying (less fees)
    /// @param receiver Address where the resulting PTs and YTs will be transferred to
    function issue(
        address adapter,
        uint256 maturity,
        uint256 targetIn,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal) {
        // pull target
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: targetIn }),
            msg.sender,
            signature
        );
        uBal = divider.issue(adapter, maturity, targetIn);
        ERC20(divider.pt(adapter, maturity)).transfer(receiver, uBal); // Send PTs to the receiver
        ERC20(divider.yt(adapter, maturity)).transfer(receiver, uBal); // Send YT to the receiver
    }

    /// @notice Mint PTs & YTs of a specific Series from Underlying
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series [unix time]
    /// @param underlyingIn Amount of Underlying to issue with
    /// @dev The balance of PTs and YTs minted will be the same value in units of underlying (less fees)
    /// @param receiver Address where the resulting PTs and YTs will be transferred to
    function issueFromUnderlying(
        address adapter,
        uint256 maturity,
        uint256 underlyingIn,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal) {
        // pull underlying
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: underlyingIn }),
            msg.sender,
            signature
        );
        uBal = divider.issue(adapter, maturity, Adapter(adapter).wrapUnderlying(underlyingIn));
        ERC20(divider.pt(adapter, maturity)).transfer(receiver, uBal); // Send PTs to the receiver
        ERC20(divider.yt(adapter, maturity)).transfer(receiver, uBal); // Send YT to the receiver
    }

    /// @notice Reconstitute Target by burning PT and YT
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Amount of PT and YT to burn
    /// @param receiver Address where the resulting Target will be transferred
    function combine(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        address receiver,
        bytes memory permit
    ) external returns (uint256 tBal) {
        // pull underlying
        (IPermit2.PermitBatchTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitBatchTransferFrom, bytes)
        );

        IPermit2.SignatureTransferDetails[] memory sigs = new IPermit2.SignatureTransferDetails[](2);
        sigs[0] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal });
        sigs[1] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal });

        permit2.permitTransferFrom(pmsg, sigs, msg.sender, signature);
        ERC20(Adapter(adapter).target()).safeTransfer(receiver, tBal = divider.combine(adapter, maturity, uBal)); // Send Target to the receiver
    }

    /// @notice Reconstitute Target by burning PT and YT and unwrapping it
    /// @dev Explicitly burns YTs before maturity, and implicitly does it at/after maturity through `_collect()`
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param amt Amount of PT and YT to burn
    /// @param receiver Address where the resulting Underlying will be transferred to
    function combineToUnderlying(
        address adapter,
        uint256 maturity,
        uint256 amt,
        address receiver,
        bytes memory permit
    ) external returns (uint256 uBal) {
        // pull underlying
        (IPermit2.PermitBatchTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitBatchTransferFrom, bytes)
        );

        IPermit2.SignatureTransferDetails[] memory sigs = new IPermit2.SignatureTransferDetails[](2);
        sigs[0] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: amt });
        sigs[1] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: amt });

        permit2.permitTransferFrom(pmsg, sigs, msg.sender, signature);
        uint256 tBal = divider.combine(adapter, maturity, amt);
        ERC20(Adapter(adapter).underlying()).safeTransfer(receiver, uBal = Adapter(adapter).unwrapTarget(tBal)); // Send Underlying to the receiver
    }

    /* ========== ADMIN ========== */

    /// @notice Enable or disable a factory
    /// @param f Factory's address
    /// @param isOn Flag setting this factory to enabled or disabled
    function setFactory(address f, bool isOn) external requiresTrust {
        if (factories[f] == isOn) revert Errors.ExistingValue();
        factories[f] = isOn;
        emit FactoryChanged(f, isOn);
    }

    /// @notice Update the address for the Space Factory
    /// @param newSpaceFactory The Space Factory addresss to set
    function setSpaceFactory(address newSpaceFactory) external requiresTrust {
        emit SpaceFactoryChanged(address(spaceFactory), newSpaceFactory);
        spaceFactory = SpaceFactoryLike(newSpaceFactory);
    }

    /// @notice Update the address for the Pool Manager
    /// @param newPoolManager The Pool Manager addresss to set
    function setPoolManager(address newPoolManager) external requiresTrust {
        emit PoolManagerChanged(address(poolManager), newPoolManager);
        poolManager = PoolManager(newPoolManager);
    }

    /// @dev Verifies an Adapter and optionally adds the Target to the money market
    /// @param adapter Adapter to verify
    function verifyAdapter(address adapter, bool addToPool) public requiresTrust {
        _verifyAdapter(adapter, addToPool);
    }

    function _verifyAdapter(address adapter, bool addToPool) private {
        verified[adapter] = true;
        if (addToPool && address(poolManager) != address(0)) poolManager.addTarget(Adapter(adapter).target(), adapter);
        emit AdapterVerified(adapter);
    }

    /// @notice Onboard a single Adapter w/o needing a factory
    /// @dev Called by a trusted address, approves Target for issuance, and onboards adapter to the Divider
    /// @param adapter Adapter to onboard
    /// @param addAdapter Whether to call divider.addAdapter or not (useful e.g when upgrading Periphery)
    function onboardAdapter(address adapter, bool addAdapter) public {
        if (!divider.permissionless() && !isTrusted[msg.sender]) revert Errors.OnlyPermissionless();
        _onboardAdapter(adapter, addAdapter);
    }

    function _onboardAdapter(address adapter, bool addAdapter) private {
        ERC20 target = ERC20(Adapter(adapter).target());
        target.safeApprove(address(divider), type(uint256).max);
        target.safeApprove(address(adapter), type(uint256).max);
        ERC20(Adapter(adapter).underlying()).safeApprove(address(adapter), type(uint256).max);
        if (addAdapter) divider.addAdapter(adapter);
        emit AdapterOnboarded(adapter);
    }

    /* ========== INTERNAL UTILS ========== */

    function _swap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        bytes32 poolId,
        uint256 minAccepted,
        address payable receiver
    ) internal returns (uint256 amountOut) {
        // approve vault to spend tokenIn
        ERC20(assetIn).safeApprove(address(balancerVault), amountIn);

        BalancerVault.SingleSwap memory request = BalancerVault.SingleSwap({
            poolId: poolId,
            kind: BalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(assetIn),
            assetOut: IAsset(assetOut),
            amount: amountIn,
            userData: hex""
        });

        BalancerVault.FundManagement memory funds = BalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: receiver,
            toInternalBalance: false
        });

        amountOut = balancerVault.swap(request, funds, minAccepted, type(uint256).max);
        emit Swapped(msg.sender, poolId, assetIn, assetOut, amountIn, amountOut, msg.sig);
    }

    function _swapPTsForTarget(
        address adapter,
        uint256 maturity,
        uint256 ptBal,
        uint256 minAccepted,
        bytes memory permit
    ) internal returns (uint256 tBal) {
        // pull PTs
        (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
            permit,
            (IPermit2.PermitTransferFrom, bytes)
        );
        permit2.permitTransferFrom(
            pmsg,
            IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: ptBal }),
            msg.sender,
            signature
        );

        if (divider.mscale(adapter, maturity) > 0) {
            tBal = divider.redeem(adapter, maturity, ptBal);
        } else {
            tBal = _swap(
                divider.pt(adapter, maturity),
                Adapter(adapter).target(),
                ptBal,
                BalancerPool(spaceFactory.pools(adapter, maturity)).getPoolId(),
                minAccepted,
                payable(address(this))
            ); // swap PTs for underlying
        }
    }

    function _swapTargetForPTs(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minAccepted,
        address receiver
    ) internal returns (uint256 ptBal) {
        address pt = divider.pt(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        ptBal = _swap(Adapter(adapter).target(), pt, tBal, pool.getPoolId(), minAccepted, payable(receiver)); // swap target for Principal Tokens
    }

    function _swapYTsForTarget(
        address sender,
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        bytes memory permit
    ) internal returns (uint256 tBal) {
        // Because there's some margin of error in the pricing functions here, smaller
        // swaps will be unreliable. Tokens with more than 18 decimals are not supported.
        if (ytBal * 10**(18 - ERC20(divider.yt(adapter, maturity)).decimals()) <= MIN_YT_SWAP_IN)
            revert Errors.SwapTooSmall();

        // Transfer YTs into this contract if needed
        if (sender != address(this)) {
            (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
                permit,
                (IPermit2.PermitTransferFrom, bytes)
            );
            permit2.permitTransferFrom(
                pmsg,
                IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: ytBal }),
                msg.sender,
                signature
            );
        }

        // Calculate target to borrow by calling AMM
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        bytes32 poolId = pool.getPoolId();
        (uint256 pti, uint256 targeti) = pool.getIndices();
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolId);
        // Determine how much Target we'll need in to get `ytBal` balance of PT out
        // (space doesn't directly use of the fields from `SwapRequest` beyond `poolId`, so the values after are placeholders)
        uint256 targetToBorrow = BalancerPool(pool).onSwap(
            BalancerPool.SwapRequest({
                kind: BalancerVault.SwapKind.GIVEN_OUT,
                tokenIn: tokens[targeti],
                tokenOut: tokens[pti],
                amount: ytBal,
                poolId: poolId,
                lastChangeBlock: 0,
                from: address(0),
                to: address(0),
                userData: ""
            }),
            balances[targeti],
            balances[pti]
        );

        // Flash borrow target (following actions in `onFlashLoan`)
        tBal = _flashBorrowAndSwapFromYTs(adapter, maturity, ytBal, targetToBorrow);
    }

    /// @return tAmount if mode = 0, target received from selling YTs, otherwise, returns 0
    /// @return issued returns amount of YTs issued (and received) except first provision which returns 0
    /// @return lpShares LP Shares received from adding liquidity to a Space
    function _addLiquidity(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint8 mode,
        uint256 minBptOut,
        address receiver,
        bytes memory permit
    )
        internal
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        // (1) compute target, issue PTs & YTs & add liquidity to space
        (issued, lpShares) = _computeIssueAddLiq(adapter, maturity, tBal, minBptOut, receiver);

        if (issued > 0) {
            // issue = 0 means that we are on the first pool provision or that the pt:target ratio is 0:target
            if (mode == 0) {
                // (2) Sell YTs
                tAmount = _swapYTsForTarget(address(this), adapter, maturity, issued, permit);

                // (3) Send remaining Target to the receiver
                ERC20(Adapter(adapter).target()).safeTransfer(receiver, tAmount);
            } else {
                // (4) Send YTs to the receiver
                ERC20(divider.yt(adapter, maturity)).safeTransfer(receiver, issued);
            }
        }
    }

    /// @dev Calculates amount of PTs in target terms (see description on `_computeTarget`) then issues
    /// PTs and YTs with the calculated amount and finally adds liquidity to space with the PTs issued
    /// and the diff between the target initially passed and the calculated amount
    function _computeIssueAddLiq(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 minBptOut,
        address receiver
    ) internal returns (uint256 issued, uint256 lpShares) {
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        // Compute target
        (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(pool.getPoolId());
        (uint256 pti, uint256 targeti) = pool.getIndices(); // Ensure we have the right token Indices

        // We do not add Principal Token liquidity if it haven't been initialized yet
        bool ptInitialized = balances[pti] != 0;
        uint256 ptBalInTarget = ptInitialized ? _computeTarget(adapter, balances[pti], balances[targeti], tBal) : 0;

        // Issue PT & YT (skip if first pool provision)
        issued = ptBalInTarget > 0 ? divider.issue(adapter, maturity, ptBalInTarget) : 0;

        // Add liquidity to Space & send the LP Shares to recipient
        uint256[] memory amounts = new uint256[](2);
        amounts[targeti] = tBal - ptBalInTarget;
        amounts[pti] = issued;
        lpShares = _addLiquidityToSpace(pool, PoolLiquidity(tokens, amounts, minBptOut), receiver);
    }

    /// @dev Based on pt:target ratio from current pool reserves and tBal passed
    /// calculates amount of tBal needed so as to issue PTs that would keep the ratio
    function _computeTarget(
        address adapter,
        uint256 ptiBal,
        uint256 targetiBal,
        uint256 tBal
    ) internal returns (uint256 tBalForIssuance) {
        return
            tBal.fmul(
                ptiBal.fdiv(
                    Adapter(adapter).scale().fmul(FixedMath.WAD - Adapter(adapter).ifee()).fmul(targetiBal) + ptiBal
                )
            );
    }

    function _removeLiquidity(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        uint256[] memory minAmountsOut,
        uint256 minAccepted,
        bool intoTarget,
        address receiver,
        bytes memory permit
    ) internal returns (uint256 tBal, uint256 ptBal) {
        // (0) Pull LP tokens from sender
        {
            (IPermit2.PermitTransferFrom memory pmsg, bytes memory signature) = abi.decode(
                permit,
                (IPermit2.PermitTransferFrom, bytes)
            );
            permit2.permitTransferFrom(
                pmsg,
                IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: lpBal }),
                msg.sender,
                signature
            );
        }

        // (1) Remove liquidity from Space
        {
            // address target = Adapter(adapter).target();
            BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
            address pt = divider.pt(adapter, maturity);
            uint256 _ptBal;
            (tBal, _ptBal) = _removeLiquidityFromSpace(
                pool.getPoolId(),
                pt,
                Adapter(adapter).target(),
                minAmountsOut,
                lpBal
            );
            if (divider.mscale(adapter, maturity) > 0) {
                if (uint256(Adapter(adapter).level()).redeemRestricted()) {
                    ptBal = _ptBal;
                } else {
                    // (2) Redeem PTs for Target
                    tBal += divider.redeem(adapter, maturity, _ptBal);
                }
            } else {
                // (2) Sell PTs for Target (if there are)
                if (_ptBal > 0 && intoTarget) {
                    tBal += _swap(
                        pt,
                        Adapter(adapter).target(),
                        _ptBal,
                        pool.getPoolId(),
                        minAccepted,
                        payable(address(this))
                    );
                } else {
                    ptBal = _ptBal;
                }
            }
            if (ptBal > 0) ERC20(pt).transfer(receiver, ptBal); // Send PTs to the receiver
        }
    }

    /// @notice Initiates a flash loan of Target, swaps target amount to PTs and combines
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param ytBalIn YT amount the user has sent in
    /// @param amountToBorrow target amount to borrow
    /// @return tBal amount of Target obtained from a sale of YTs
    function _flashBorrowAndSwapFromYTs(
        address adapter,
        uint256 maturity,
        uint256 ytBalIn,
        uint256 amountToBorrow
    ) internal returns (uint256 tBal) {
        ERC20 target = ERC20(Adapter(adapter).target());
        uint256 decimals = target.decimals();
        uint256 acceptableError = decimals < 9 ? 1 : PRICE_ESTIMATE_ACCEPTABLE_ERROR / 10**(18 - decimals);
        bytes memory data = abi.encode(adapter, uint256(maturity), ytBalIn, ytBalIn - acceptableError, true);
        bool result = Adapter(adapter).flashLoan(this, address(target), amountToBorrow, data);
        if (!result) revert Errors.FlashBorrowFailed();
        tBal = target.balanceOf(address(this));
    }

    /// @notice Initiates a flash loan of Target, issues PTs/YTs and swaps the PTs to Target
    /// @param adapter adapter
    /// @param maturity taturity
    /// @param targetIn Target amount the user has sent in
    /// @param amountToBorrow Target amount to borrow
    /// @param minOut minimum amount of Target accepted out for the issued PTs
    /// @return targetBal amount of Target remaining after the flashloan has been paid back
    /// @return ytBal amount of YTs issued with the borrowed Target and the Target sent in
    function _flashBorrowAndSwapToYTs(
        address adapter,
        uint256 maturity,
        uint256 targetIn,
        uint256 amountToBorrow,
        uint256 minOut
    ) internal returns (uint256 targetBal, uint256 ytBal) {
        bytes memory data = abi.encode(adapter, uint256(maturity), targetIn, minOut, false);
        bool result = Adapter(adapter).flashLoan(this, Adapter(adapter).target(), amountToBorrow, data);
        if (!result) revert Errors.FlashBorrowFailed();

        targetBal = ERC20(Adapter(adapter).target()).balanceOf(address(this));
        ytBal = ERC20(divider.yt(adapter, maturity)).balanceOf(address(this));
        emit YTsPurchased(msg.sender, adapter, maturity, targetIn, targetBal, ytBal);
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address, /* token */
        uint256 amountBorrrowed,
        uint256, /* fee */
        bytes calldata data
    ) external returns (bytes32) {
        (address adapter, uint256 maturity, uint256 amountIn, uint256 minOut, bool ytToTarget) = abi.decode(
            data,
            (address, uint256, uint256, uint256, bool)
        );

        if (msg.sender != address(adapter)) revert Errors.FlashUntrustedBorrower();
        if (initiator != address(this)) revert Errors.FlashUntrustedLoanInitiator();
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));

        if (ytToTarget) {
            ERC20 target = ERC20(Adapter(adapter).target());

            // Swap Target for PTs
            uint256 ptBal = _swap(
                address(target),
                divider.pt(adapter, maturity),
                target.balanceOf(address(this)),
                pool.getPoolId(),
                minOut, // min pt out
                payable(address(this))
            );

            // Combine PTs and YTs
            divider.combine(adapter, maturity, ptBal < amountIn ? ptBal : amountIn);
        } else {
            // Issue PTs and YTs
            divider.issue(adapter, maturity, amountIn + amountBorrrowed);
            ERC20 pt = ERC20(divider.pt(adapter, maturity));

            // Swap PTs for Target
            _swap(
                address(pt),
                Adapter(adapter).target(),
                pt.balanceOf(address(this)),
                pool.getPoolId(),
                minOut, // min Target out
                payable(address(this))
            ); // minOut should be close to amountBorrrowed so that minimal Target dust is sent back to the caller

            // Flashloaner contract will revert if not enough Target has been swapped out to pay back the loan
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _addLiquidityToSpace(
        BalancerPool pool,
        PoolLiquidity memory liq,
        address receiver
    ) internal returns (uint256 lpBal) {
        bytes32 poolId = pool.getPoolId();
        IAsset[] memory assets = _convertERC20sToAssets(liq.tokens);
        for (uint8 i; i < liq.tokens.length; i++) {
            // Tokens and amounts must be in same order
            liq.tokens[i].safeApprove(address(balancerVault), liq.amounts[i]);
        }

        // Behaves like EXACT_TOKENS_IN_FOR_BPT_OUT, user sends precise quantities of tokens,
        // and receives an estimated but unknown (computed at run time) quantity of BPT
        BalancerVault.JoinPoolRequest memory request = BalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: liq.amounts,
            userData: abi.encode(liq.amounts, liq.minBptOut),
            fromInternalBalance: false
        });
        lpBal = ERC20(address(pool)).balanceOf(receiver);
        balancerVault.joinPool(poolId, address(this), receiver, request);
        lpBal = ERC20(address(pool)).balanceOf(receiver) - lpBal;
    }

    function _removeLiquidityFromSpace(
        bytes32 poolId,
        address pt,
        address target,
        uint256[] memory minAmountsOut,
        uint256 lpBal
    ) internal returns (uint256 tBal, uint256 ptBal) {
        // ExitPoolRequest params
        (ERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        IAsset[] memory assets = _convertERC20sToAssets(tokens);
        BalancerVault.ExitPoolRequest memory request = BalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(lpBal),
            toInternalBalance: false
        });
        tBal = ERC20(target).balanceOf(address(this));
        ptBal = ERC20(pt).balanceOf(address(this));

        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);

        tBal = ERC20(target).balanceOf(address(this)) - tBal;
        ptBal = ERC20(pt).balanceOf(address(this)) - ptBal;
    }

    /// @notice From: https://github.com/balancer-labs/balancer-examples/blob/master/packages/liquidity-provision/contracts/LiquidityProvider.sol#L33
    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }

    /* ========== LOGS ========== */

    event FactoryChanged(address indexed factory, bool indexed isOn);
    event SpaceFactoryChanged(address oldSpaceFactory, address newSpaceFactory);
    event PoolManagerChanged(address oldPoolManager, address newPoolManager);
    event SeriesSponsored(address indexed adapter, uint256 indexed maturity, address indexed sponsor);
    event AdapterDeployed(address indexed adapter);
    event AdapterOnboarded(address indexed adapter);
    event AdapterVerified(address indexed adapter);
    event YTsPurchased(
        address indexed sender,
        address adapter,
        uint256 maturity,
        uint256 targetIn,
        uint256 targetReturned,
        uint256 ytOut
    );
    event Swapped(
        address indexed sender,
        bytes32 indexed poolId,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes4 indexed sig
    );
}
