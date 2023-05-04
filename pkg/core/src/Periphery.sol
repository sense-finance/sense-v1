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

    /// @notice ETH address
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ========== PUBLIC IMMUTABLES ========== */

    /// @notice Sense core Divider address
    Divider public immutable divider;

    /// @notice Sense core Divider address
    BalancerVault public immutable balancerVault;

    /// @notice Permit2 contract
    IPermit2 public immutable permit2;

    // 0x ExchangeProxy address. See https://docs.0x.org/developer-resources/contract-addresses
    address public immutable exchangeProxy;

    /* ========== PUBLIC MUTABLE STORAGE ========== */

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

    struct PermitData {
        IPermit2.PermitTransferFrom msg;
        bytes sig;
    }

    struct PermitBatchData {
        IPermit2.PermitBatchTransferFrom msg;
        bytes sig;
    }

    struct SwapQuote {
        ERC20 sellToken;
        ERC20 buyToken;
        uint256 amount;
        address spender;
        address payable swapTarget;
        bytes swapCallData;
    }

    struct AddLiquidityParams {
        uint256 minAccepted; // Min accepted amount of Target (from the sell of YTs)
        uint256 minBptOut; // Min BPT the user will accept out for this transaction
        uint256 deadline; // The UNIX timestamp at which our trade must be completed by - if the transaction is confirmed after this time then the transaction will fail.
    }

    struct RemoveLiquidityParams {
        uint256 minAccepted; // Min accepted when swapping PTs to underlying (only used when removing liquidity before maturity)
        uint256[] minAmountsOut; // Min accepted amounts of PTs and Target given the amount of LP shares provided
        uint256 deadline; // The UNIX timestamp at which our trade must be completed by - if the transaction is confirmed after this time then the transaction will fail.
    }

    constructor(
        address _divider,
        address _spaceFactory,
        address _balancerVault,
        address _permit2,
        address _exchangeProxy
    ) Trust(msg.sender) {
        divider = Divider(_divider);
        spaceFactory = SpaceFactoryLike(_spaceFactory);
        balancerVault = BalancerVault(_balancerVault);
        permit2 = IPermit2(_permit2);
        exchangeProxy = _exchangeProxy;
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
        bool withPool
    ) external returns (address pt, address yt) {
        (, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();
        ERC20(stake).transferFrom(msg.sender, address(this), stakeSize);
        return _sponsorSeries(adapter, maturity, withPool, stake, stakeSize);
    }

    /// @notice Sponsor a new Series in any adapter previously onboarded onto the Divider
    /// @dev Called by an external address, initializes a new series in the Divider
    /// @param adapter Adapter to associate with the Series
    /// @param maturity Maturity date for the Series, in units of unix time
    /// @param withPool Whether to deploy a Space pool or not (only works for unverified adapters)
    /// @param permit Permit to pull the tokens to swap from
    /// @param quote Quote with swap details
    function sponsorSeries(
        address adapter,
        uint256 maturity,
        bool withPool,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (address pt, address yt) {
        (, address stake, uint256 stakeSize) = Adapter(adapter).getStakeAndTarget();
        if (address(quote.sellToken) != ETH) _transferFrom(permit, address(quote.sellToken), quote.amount);
        if (address(quote.sellToken) != stake) _fillQuote(quote);

        (pt, yt) = _sponsorSeries(adapter, maturity, withPool, stake, stakeSize);

        // refund any excess stake assets
        ERC20(stake).safeTransfer(msg.sender, _balanceOf(stake, address(this)));

        // refund any remaining quote.sellToken to receiver
        _transfer(
            quote.sellToken,
            msg.sender,
            address(quote.sellToken) == ETH
                ? address(this).balance
                : _balanceOf(address(quote.sellToken), address(this))
        );
    }

    function _sponsorSeries(
        address adapter,
        uint256 maturity,
        bool withPool,
        address stake,
        uint256 stakeSize
    ) internal returns (address pt, address yt) {
        // Approve divider to withdraw stake assets
        ERC20(stake).safeApprove(address(divider), stakeSize);

        (pt, yt) = divider.initSeries(adapter, maturity, msg.sender);

        // Space pool is always created for verified adapters whilst is optional for unverified ones.
        // Automatically queueing series is only for verified adapters
        if (verified[adapter]) {
            spaceFactory.create(adapter, maturity);
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
        bytes calldata data
    ) external returns (address adapter) {
        if (!factories[f]) revert Errors.FactoryNotSupported();
        adapter = AdapterFactory(f).deployAdapter(target, data);
        emit AdapterDeployed(adapter);
        _verifyAdapter(adapter);
        _onboardAdapter(adapter, true);
    }

    /* ========== LIQUIDITY UTILS ========== */

    /// @notice Swap for PTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param amt Amount to swap for PTs
    /// @param minAccepted Min accepted amount of PT
    /// @param receiver Address to receive the PT
    /// @param permit Permit to pull the tokens to swap from
    /// @param quote Quote with swap details
    /// @dev if quote.sellToken is neither target nor underlying, it will be swapped for underlying
    /// on 0x and wrapped into the target
    /// @return ptBal amount of PT received
    function swapForPTs(
        address adapter,
        uint256 maturity,
        uint256 amt,
        uint256 deadline,
        uint256 minAccepted,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 ptBal) {
        if (address(quote.sellToken) != ETH) _transferFrom(permit, address(quote.sellToken), amt);
        ptBal = _swapTargetForPTs(
            adapter,
            maturity,
            _toTarget(adapter, amt, receiver, quote),
            deadline,
            minAccepted,
            receiver
        );
        // refund any remaining quote.sellToken to receiver
        _transfer(
            quote.sellToken,
            receiver,
            address(quote.sellToken) == ETH
                ? address(this).balance
                : _balanceOf(address(quote.sellToken), address(this))
        );
    }

    /// @notice Swap to YTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param amt Amount to sell
    /// @param targetToBorrow Amount of Target to borrow
    /// @param minAccepted Min accepted amount of YT
    /// @param receiver Address to receive the YT
    /// @param permit Permit to pull the tokens to swap from
    /// @param quote Quote with swap details
    /// @return targetBal amount of Target sent back
    /// @return ytBal amount of YT received
    /// @dev if quote.sellToken is neither target nor underlying, it will be swapped for underlying
    /// on 0x and wrapped into the target
    function swapForYTs(
        address adapter,
        uint256 maturity,
        uint256 amt,
        uint256 deadline,
        uint256 targetToBorrow,
        uint256 minAccepted,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 targetBal, uint256 ytBal) {
        if (address(quote.sellToken) != ETH) _transferFrom(permit, address(quote.sellToken), amt);

        // swap sellToken to target, borrow more target and swap to YTs
        (targetBal, ytBal) = _flashBorrowAndSwapToYTs(
            adapter,
            maturity,
            _toTarget(adapter, amt, receiver, quote),
            deadline,
            targetToBorrow,
            minAccepted
        );

        ERC20(Adapter(adapter).target()).safeTransfer(receiver, targetBal);
        ERC20(divider.yt(adapter, maturity)).safeTransfer(receiver, ytBal);
    }

    /// @notice Swap PTs of a particular series
    /// @param adapter Adapter address for the series
    /// @param maturity Maturity date for the series
    /// @param ptBal Balance of PT to sell
    /// @param minAccepted Min accepted amount of quote.buyToken the user receives
    /// @param receiver Address to receive the tokens
    /// @param permit Permit to pull PTs
    /// @param quote Quote with swap details
    /// @return amt amount of tokens received
    /// @dev if quote.buyToken is neither target nor underlying, it will unwrap target
    /// and swap it on 0x
    function swapPTs(
        address adapter,
        uint256 maturity,
        uint256 ptBal,
        uint256 deadline,
        uint256 minAccepted,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 amt) {
        amt = _swapSenseToken(adapter, maturity, ptBal, deadline, minAccepted, 0, receiver, permit, quote);
    }

    /// @notice Swap YTs of a particular series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param ytBal Balance of YTs to swap
    /// @param minAccepted Min accepted amount of tokens when selling them on Space
    /// @param receiver Address to receive the Target
    /// @param permit Permit to pull YTs
    /// @param quote Quote with swap details
    /// @return amt amount of Target received
    /// @dev if quote.buyToken is neither target nor underlying, it will unwrap target
    /// and swap it on 0x
    function swapYTs(
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        uint256 deadline,
        uint256 minAccepted,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 amt) {
        amt = _swapSenseToken(adapter, maturity, ytBal, deadline, minAccepted, 1, receiver, permit, quote);
    }

    /// @notice this function is here for backwards compatibility with AutoRoller. It does not suppport
    /// the use of `deadline` parameter. Use `swapYTs` instead.
    function swapYTsForTarget(
        address adapter,
        uint256 maturity,
        uint256 ytBal
    ) external returns (uint256 amt) {
        ERC20(divider.yt(adapter, maturity)).transferFrom(msg.sender, address(this), ytBal);
        amt = this.swapYTsForTargetHelper(
            msg.sender,
            adapter,
            maturity,
            ytBal,
            PermitData(IPermit2.PermitTransferFrom(IPermit2.TokenPermissions(ERC20(address(0)), 0), 0, 0), "0x")
        );
        _transfer(ERC20(Adapter(adapter).target()), msg.sender, amt);
    }

    function swapYTsForTargetHelper(
        address sender,
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        PermitData calldata permit
    ) external returns (uint256 amt) {
        if (msg.sender != address(this)) revert Errors.OnlyPeriphery();
        amt = _swapYTsForTarget(sender, adapter, maturity, ytBal, block.timestamp, permit);
    }

    function _swapSenseToken(
        address adapter,
        uint256 maturity,
        uint256 sellAmt,
        uint256 deadline,
        uint256 minAccepted,
        uint8 mode, // 0 = PTs, 1 = YTs
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) private returns (uint256 amt) {
        amt = (mode == 1)
            ? _swapYTsForTarget(msg.sender, adapter, maturity, sellAmt, deadline, permit)
            : _swapPTsForTarget(adapter, maturity, sellAmt, deadline, permit);
        amt = _fromTarget(adapter, amt, receiver, quote);

        if (amt < minAccepted) revert Errors.UnexpectedSwapAmount();
        _transfer(quote.buyToken, receiver, amt);
    }

    /// @notice Adds liquidity providing any Token
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param amt Amount to provide
    /// @param params AddLiquidityParams struct with the params for the addLiquidity call
    /// @param mode 0 = issues and sell YT, 1 = issue and hold YT
    /// @param receiver Address to receive the BPT
    /// @param permit Permit to pull the tokens to swap from
    /// @param quote Quote with swap details
    /// @dev see return description of _addLiquidity
    /// @dev if quote.sellToken is neither target nor underlying, it will be swapped for underlying
    /// on 0x and wrapped into the target
    function addLiquidity(
        address adapter,
        uint256 maturity,
        uint256 amt,
        AddLiquidityParams memory params,
        uint8 mode,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    )
        external
        payable
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        if (address(quote.sellToken) != ETH) _transferFrom(permit, address(quote.sellToken), amt);
        (tAmount, issued, lpShares) = _addLiquidity(
            adapter,
            maturity,
            _toTarget(adapter, amt, receiver, quote),
            params,
            mode,
            receiver,
            permit
        );
    }

    /// @notice Removes liquidity providing an amount of LP tokens and returns underlying
    /// @dev More info on `minAmountsOut`: https://github.com/balancer-labs/docs-developers/blob/main/resources/joins-and-exits/pool-exits.md#minamountsout
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param lpBal Balance of LP tokens to provide
    /// @param params RemoveLiquidityParams struct with the params for the removeLiquidity call
    /// @param swapPTs Whether to swap PTs or not. If false, it will transfer PTs to the user
    /// @param receiver Address to receive the Underlying
    /// @param permit Permit to pull the LP tokens
    /// @param quote Quote with swap details
    /// @return amt amount of tokens received and ptBal PTs (in case it's called after maturity and redeem is restricted or intoTarget is false)
    /// @dev if quote.buyToken is neither target nor underlying, it will unwrap target
    /// and swap it on 0x
    /// if quote.buyToken is PT, it will return target and PTs
    function removeLiquidity(
        address adapter,
        uint256 maturity,
        uint256 lpBal,
        RemoveLiquidityParams memory params,
        bool swapPTs,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 amt, uint256 ptBal) {
        (amt, ptBal) = _removeLiquidity(adapter, maturity, lpBal, params, swapPTs, receiver, permit);
        amt = _fromTarget(adapter, amt, receiver, quote);
        _transfer(quote.buyToken, receiver, amt);
    }

    /* ========== UTILS ========== */

    /// @notice Mint PTs & YTs of a specific Series
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series [unix time]
    /// @param amt Amount to issue with
    /// @dev The balance of PTs and YTs minted will be the same value in units of underlying (less fees)
    /// @param receiver Address where the resulting PTs and YTs will be transferred to
    /// @param permit Permit to pull tokens
    /// @param quote Quote with swap details
    /// @return uBal Amount of PTs and YTs minted
    /// @dev if quote.sellToken is neither target nor underlying, it will swap on 0x and wrap to target
    /// and swap it on 0x
    function issue(
        address adapter,
        uint256 maturity,
        uint256 amt,
        address receiver,
        PermitData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 uBal) {
        if (address(quote.sellToken) != ETH) _transferFrom(permit, address(quote.sellToken), amt);
        uBal = divider.issue(adapter, maturity, _toTarget(adapter, amt, receiver, quote));
        ERC20(divider.pt(adapter, maturity)).transfer(receiver, uBal); // Send PTs to the receiver
        ERC20(divider.yt(adapter, maturity)).transfer(receiver, uBal); // Send YT to the receiver
    }

    /// @notice Reconstitute Target by burning PT and YT
    /// @param adapter Adapter address for the Series
    /// @param maturity Maturity date for the Series
    /// @param uBal Amount of PT and YT to burn
    /// @param receiver Address where the resulting Target will be transferred
    /// @param permit Permit to pull PT and YT
    /// @param quote Quote with swap details
    /// @return amt Amount of tokens received from reconstituting target
    /// @dev if quote.buyToken is neither target nor underlying, it will unwrap target
    /// and swap it on 0x
    function combine(
        address adapter,
        uint256 maturity,
        uint256 uBal,
        address receiver,
        PermitBatchData calldata permit,
        SwapQuote calldata quote
    ) external payable returns (uint256 amt) {
        IPermit2.SignatureTransferDetails[] memory sigs = new IPermit2.SignatureTransferDetails[](2);
        sigs[0] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal });
        sigs[1] = IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: uBal });

        // pull underlying
        permit2.permitTransferFrom(permit.msg, sigs, msg.sender, permit.sig);
        amt = _fromTarget(adapter, divider.combine(adapter, maturity, uBal), receiver, quote);
        _transfer(quote.buyToken, receiver, amt);
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

    /// @dev Verifies an Adapter
    /// @param adapter Adapter to verify
    function verifyAdapter(address adapter) public requiresTrust {
        _verifyAdapter(adapter);
    }

    function _verifyAdapter(address adapter) private {
        verified[adapter] = true;
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

    function _balancerSwap(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 deadline,
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

        amountOut = balancerVault.swap(request, funds, minAccepted, deadline);
        emit Swapped(msg.sender, poolId, assetIn, assetOut, amountIn, amountOut, msg.sig);
    }

    function _swapPTsForTarget(
        address adapter,
        uint256 maturity,
        uint256 ptBal,
        uint256 deadline,
        PermitData calldata permit
    ) internal returns (uint256 tBal) {
        _transferFrom(permit, divider.pt(adapter, maturity), ptBal);

        if (divider.mscale(adapter, maturity) > 0 && !uint256(Adapter(adapter).level()).redeemRestricted()) {
            tBal = divider.redeem(adapter, maturity, ptBal);
        } else {
            tBal = _balancerSwap(
                divider.pt(adapter, maturity),
                Adapter(adapter).target(),
                ptBal,
                deadline,
                BalancerPool(spaceFactory.pools(adapter, maturity)).getPoolId(),
                0,
                payable(address(this))
            );
        }
    }

    function _swapTargetForPTs(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        uint256 deadline,
        uint256 minAccepted,
        address receiver
    ) internal returns (uint256 ptBal) {
        address pt = divider.pt(adapter, maturity);
        BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
        ptBal = _balancerSwap(
            Adapter(adapter).target(),
            pt,
            tBal,
            deadline,
            pool.getPoolId(),
            minAccepted,
            payable(receiver)
        ); // swap target for PTs
    }

    function _swapYTsForTarget(
        address sender,
        address adapter,
        uint256 maturity,
        uint256 ytBal,
        uint256 deadline,
        PermitData calldata permit
    ) internal returns (uint256 tBal) {
        // Because there's some margin of error in the pricing functions here, smaller
        // swaps will be unreliable. Tokens with more than 18 decimals are not supported.
        if (ytBal * 10**(18 - ERC20(divider.yt(adapter, maturity)).decimals()) <= MIN_YT_SWAP_IN)
            revert Errors.SwapTooSmall();

        // Transfer YTs into this contract if needed
        if (sender != address(this) && msg.sender != address(this))
            _transferFrom(permit, divider.yt(adapter, maturity), ytBal);

        // Calculate target to borrow by calling AMM
        uint256 targetToBorrow;
        {
            BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
            bytes32 poolId = pool.getPoolId();
            (uint256 pti, uint256 targeti) = pool.getIndices();
            (ERC20[] memory tokens, uint256[] memory balances, ) = balancerVault.getPoolTokens(poolId);
            // Determine how much Target we'll need in to get `ytBal` balance of PT out
            // (space doesn't directly use of the fields from `SwapRequest` beyond `poolId`, so the values after are placeholders)
            targetToBorrow = BalancerPool(pool).onSwap(
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
        }

        // Flash borrow target (following actions in `onFlashLoan`)
        tBal = _flashBorrowAndSwapFromYTs(adapter, maturity, abi.encode(ytBal, targetToBorrow, deadline));
    }

    /// @return tAmount if mode = 0, target received from selling YTs, otherwise, returns 0
    /// @return issued returns amount of YTs issued (and received) except first provision which returns 0
    /// @return lpShares LP Shares received from adding liquidity to a Space
    function _addLiquidity(
        address adapter,
        uint256 maturity,
        uint256 tBal,
        AddLiquidityParams memory params,
        uint8 mode,
        address receiver,
        PermitData calldata permit
    )
        internal
        returns (
            uint256 tAmount,
            uint256 issued,
            uint256 lpShares
        )
    {
        // 1. Compute target, issue PTs & YTs & add liquidity to space
        (issued, lpShares) = _computeIssueAddLiq(adapter, maturity, tBal, params.minBptOut, receiver);

        if (issued > 0) {
            // issue = 0 means that we are on the first pool provision or that the pt:target ratio is 0:target
            if (mode == 0) {
                // 2. Sell YTs
                tAmount = _swapYTsForTarget(
                    address(this),
                    adapter,
                    maturity,
                    issued,
                    params.deadline,
                    permit // we send permit thought it won't be used
                );
                // Check that we got enough target
                if (tAmount < params.minAccepted) revert Errors.UnexpectedSwapAmount();

                // 3. Send remaining Target to the receiver
                ERC20(Adapter(adapter).target()).safeTransfer(receiver, tAmount);
            } else {
                // 2. Send YTs to the receiver
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
        RemoveLiquidityParams memory params,
        bool swapPTs,
        address receiver,
        PermitData calldata permit
    ) internal returns (uint256 tBal, uint256 ptBal) {
        bytes32 poolId;
        {
            BalancerPool pool = BalancerPool(spaceFactory.pools(adapter, maturity));
            _transferFrom(permit, address(pool), lpBal);
            poolId = pool.getPoolId();
        }

        // 1. Remove liquidity from Space
        address pt = divider.pt(adapter, maturity);
        uint256 _ptBal;
        (tBal, _ptBal) = _removeLiquidityFromSpace(poolId, pt, Adapter(adapter).target(), params.minAmountsOut, lpBal);

        if (divider.mscale(adapter, maturity) > 0) {
            if (uint256(Adapter(adapter).level()).redeemRestricted()) {
                ptBal = _ptBal;
            } else {
                // 2. Redeem PTs for Target
                tBal += divider.redeem(adapter, maturity, _ptBal);
            }
        } else {
            // 2. Sell PTs for Target (if there are)
            if (_ptBal > 0 && swapPTs) {
                tBal += _balancerSwap(
                    pt,
                    Adapter(adapter).target(),
                    _ptBal,
                    params.deadline,
                    poolId,
                    params.minAccepted,
                    payable(address(this))
                );
            } else {
                ptBal = _ptBal;
            }
        }
        if (ptBal > 0) ERC20(pt).transfer(receiver, ptBal);
    }

    /// @notice Initiates a flash loan of Target, swaps target amount to PTs and combines
    /// @param adapter adapter
    /// @param maturity maturity
    /// @param data abi.encoded data:
    /// - YT amount the user has sent in
    /// - target amount to borrow
    /// - deadline for the swap
    /// @return tBal amount of Target obtained from a sale of YTs
    function _flashBorrowAndSwapFromYTs(
        address adapter,
        uint256 maturity,
        bytes memory data
    ) internal returns (uint256 tBal) {
        ERC20 target = ERC20(Adapter(adapter).target());
        uint256 decimals = target.decimals();
        uint256 acceptableError = decimals < 9 ? 1 : PRICE_ESTIMATE_ACCEPTABLE_ERROR / 10**(18 - decimals);
        (uint256 ytBalIn, uint256 amountToBorrow, uint256 deadline) = abi.decode(data, (uint256, uint256, uint256));
        bool result = Adapter(adapter).flashLoan(
            this,
            address(target),
            amountToBorrow,
            abi.encode(adapter, uint256(maturity), ytBalIn, ytBalIn - acceptableError, deadline, true)
        );
        if (!result) revert Errors.FlashBorrowFailed();
        tBal = _balanceOf(address(target), address(this));
    }

    /// @notice Initiates a flash loan of Target, issues PTs/YTs and swaps the PTs to Target
    /// @param adapter adapter
    /// @param maturity taturity
    /// @param targetIn Target amount the user has sent in
    /// @param amountToBorrow Target amount to borrow
    /// @param minAccepted minimum amount of Target accepted out for the issued PTs
    /// @return targetBal amount of Target remaining after the flashloan has been paid back
    /// @return ytBal amount of YTs issued with the borrowed Target and the Target sent in
    function _flashBorrowAndSwapToYTs(
        address adapter,
        uint256 maturity,
        uint256 targetIn,
        uint256 deadline,
        uint256 amountToBorrow,
        uint256 minAccepted
    ) internal returns (uint256 targetBal, uint256 ytBal) {
        bool result = Adapter(adapter).flashLoan(
            this,
            Adapter(adapter).target(),
            amountToBorrow,
            abi.encode(adapter, uint256(maturity), targetIn, minAccepted, deadline, false)
        );
        if (!result) revert Errors.FlashBorrowFailed();

        targetBal = _balanceOf(Adapter(adapter).target(), address(this));
        ytBal = _balanceOf(divider.yt(adapter, maturity), address(this));
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
        (
            address adapter,
            uint256 maturity,
            uint256 amountIn,
            uint256 minAccepted,
            uint256 deadline,
            bool ytToTarget
        ) = abi.decode(data, (address, uint256, uint256, uint256, uint256, bool));

        if (msg.sender != address(adapter)) revert Errors.FlashUntrustedBorrower();
        if (initiator != address(this)) revert Errors.FlashUntrustedLoanInitiator();

        address target = Adapter(adapter).target();
        if (ytToTarget) {
            // Swap Target for PTs
            uint256 ptBal = _balancerSwap(
                target,
                divider.pt(adapter, maturity),
                _balanceOf(target, address(this)),
                deadline,
                BalancerPool(spaceFactory.pools(adapter, maturity)).getPoolId(),
                minAccepted, // min pt out
                payable(address(this))
            );

            // Combine PTs and YTs
            divider.combine(adapter, maturity, ptBal < amountIn ? ptBal : amountIn);
        } else {
            // Issue PTs and YTs
            divider.issue(adapter, maturity, amountIn + amountBorrrowed);
            address pt = divider.pt(adapter, maturity);

            // Swap PTs for Target
            _balancerSwap(
                pt,
                target,
                _balanceOf(pt, address(this)),
                deadline,
                BalancerPool(spaceFactory.pools(adapter, maturity)).getPoolId(),
                minAccepted, // min Target accepted
                payable(address(this))
            ); // minAccepted should be close to amountBorrrowed so that minimal Target dust is sent back to the caller

            // Flashloaner contract will revert if not enough Target has been swapped out to pay back the loan
        }

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _addLiquidityToSpace(
        BalancerPool pool,
        PoolLiquidity memory liq,
        address receiver
    ) internal returns (uint256 lpBal) {
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
        lpBal = _balanceOf(address(pool), receiver);
        balancerVault.joinPool(pool.getPoolId(), address(this), receiver, request);
        lpBal = _balanceOf(address(pool), receiver) - lpBal;
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
        BalancerVault.ExitPoolRequest memory request = BalancerVault.ExitPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            minAmountsOut: minAmountsOut,
            userData: abi.encode(lpBal),
            toInternalBalance: false
        });
        tBal = _balanceOf(target, address(this));
        ptBal = _balanceOf(pt, address(this));

        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);

        tBal = _balanceOf(target, address(this)) - tBal;
        ptBal = _balanceOf(pt, address(this)) - ptBal;
    }

    // @dev Swaps ETH->ERC20, ERC20->ERC20 or ERC20->ETH held by this contract using a 0x-API quote
    function _fillQuote(SwapQuote calldata quote) internal returns (uint256 boughtAmount) {
        if (quote.sellToken == quote.buyToken) return 0; // No swap if the tokens are the same.
        if (quote.swapTarget != exchangeProxy) revert Errors.InvalidExchangeProxy();

        // Give `spender` an infinite allowance to spend this contract's `sellToken`.
        if (address(quote.sellToken) != ETH)
            ERC20(address(quote.sellToken)).safeApprove(quote.spender, type(uint256).max);

        uint256 sellAmount = address(quote.sellToken) == ETH
            ? address(this).balance
            : _balanceOf(address(quote.sellToken), address(this));

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, bytes memory res) = quote.swapTarget.call{ value: msg.value }(quote.swapCallData);
        if (!success) revert Errors.ZeroExSwapFailed(res);

        // We assume the Periphery does not hold tokens so boughtAmount is always it's balance
        boughtAmount = address(quote.buyToken) == ETH
            ? address(this).balance
            : _balanceOf(address(quote.buyToken), address(this));
        sellAmount =
            sellAmount -
            (
                address(quote.sellToken) == ETH
                    ? address(this).balance
                    : _balanceOf(address(quote.sellToken), address(this))
            );
        if (boughtAmount == 0 || sellAmount == 0) revert Errors.ZeroSwapAmt();

        emit BoughtTokens(address(quote.sellToken), address(quote.buyToken), sellAmount, boughtAmount);
    }

    /// @notice Given an amount and a quote, decides whether it needs to wrap and make a swap on 0x,
    /// simply wrap tokens or do nothing
    function _toTarget(
        address adapter,
        uint256 _amt,
        address receiver,
        SwapQuote calldata quote
    ) internal returns (uint256 amt) {
        if (address(quote.sellToken) == Adapter(adapter).target()) {
            amt = _amt;
        } else if (address(quote.sellToken) == Adapter(adapter).underlying()) {
            amt = Adapter(adapter).wrapUnderlying(_amt);
        } else {
            // sell tokens for underlying and wrap into target
            amt = Adapter(adapter).wrapUnderlying(_fillQuote(quote));

            // refund any remaining quote.sellToken to receiver
            _transfer(
                quote.sellToken,
                receiver,
                address(quote.sellToken) == ETH
                    ? address(this).balance
                    : _balanceOf(address(quote.sellToken), address(this))
            );
        }
    }

    /// @notice Given an amount and a quote, decides whether it needs to unwrap and make a swap on 0x,
    /// simply unwrap tokens or do nothing
    /// @dev when swapping via 0x, the quote needs the amount of underlying that will be received from
    /// the unwrapTarget. This calculation is done off-chain.
    function _fromTarget(
        address adapter,
        uint256 _amt,
        address receiver,
        SwapQuote calldata quote
    ) internal returns (uint256 amt) {
        if (address(quote.buyToken) == Adapter(adapter).target()) {
            amt = _amt;
        } else if (address(quote.buyToken) == Adapter(adapter).underlying()) {
            amt = Adapter(adapter).unwrapTarget(_amt);
        } else {
            Adapter(adapter).unwrapTarget(_amt);
            amt = _fillQuote(quote);
            // refund excess tokens to receiver
            _transfer(quote.sellToken, receiver, _balanceOf(address(quote.sellToken), address(this)));
        }
    }

    function _transferFrom(
        PermitData calldata permit,
        address token,
        uint256 amt
    ) internal {
        // Generate calldata for a standard safeTransferFrom call.
        bytes memory inputData = abi.encodeCall(ERC20.transferFrom, (msg.sender, address(this), amt));

        bool success; // Call the token contract as normal, capturing whether it succeeded.
        assembly {
            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(eq(mload(0), 1), iszero(returndatasize())),
                // Counterintuitively, this call() must be positioned after the or() in the
                // surrounding and() because and() evaluates its arguments from right to left.
                // We use 0 and 32 to copy up to 32 bytes of return data into the first slot of scratch space.
                call(gas(), token, 0, add(inputData, 32), mload(inputData), 0, 32)
            )
        }

        // We'll fall back to using Permit2 if calling transferFrom on the token directly reverted.
        if (!success)
            permit2.permitTransferFrom(
                permit.msg,
                IPermit2.SignatureTransferDetails({ to: address(this), requestedAmount: amt }),
                msg.sender,
                permit.sig
            );
    }

    function _transfer(
        ERC20 token,
        address receiver,
        uint256 amt
    ) internal {
        if (amt > 0) {
            if (address(token) == ETH) {
                (bool sent, ) = receiver.call{ value: amt }("");
                if (!sent) revert Errors.TransferFailed();
            } else {
                token.safeTransfer(receiver, amt);
            }
        }
    }

    function _balanceOf(address token, address user) internal returns (uint256 amt) {
        amt = ERC20(token).balanceOf(user);
    }

    /// @notice From: https://github.com/balancer-labs/balancer-examples/blob/master/packages/liquidity-provision/contracts/LiquidityProvider.sol#L33
    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(ERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        assembly {
            assets := tokens
        }
    }

    // required for refunds
    receive() external payable {}

    /* ========== LOGS ========== */

    event FactoryChanged(address indexed factory, bool indexed isOn);
    event SpaceFactoryChanged(address oldSpaceFactory, address newSpaceFactory);
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
    event BoughtTokens(
        address indexed sellToken,
        address indexed buyToken,
        uint256 sellAmount,
        uint256 indexed boughtAmount
    );
}
