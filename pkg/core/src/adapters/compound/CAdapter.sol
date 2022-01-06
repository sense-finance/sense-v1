// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { FixedMath } from "../../external/FixedMath.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { CropAdapter } from "../CropAdapter.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

interface CTokenInterface {
    /// @notice cToken is convertible into an ever increasing quantity of the underlying asset, as interest accrues in
    /// the market. This function returns the exchange rate between a cToken and the underlying asset.
    /// @dev returns the current exchange rate as an uint, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals).
    function exchangeRateCurrent() external returns (uint256);

    /// @notice Calculates the exchange rate from the underlying to the CToken
    /// @dev This function does not accrue interest before calculating the exchange rate
    /// @return Calculated exchange rate scaled by 1e18
    function exchangeRateStored() external view returns (uint256);

    function decimals() external view returns (uint8);

    function underlying() external view returns (address);

    /// The mint function transfers an asset into the protocol, which begins accumulating interest based
    /// on the current Supply Rate for the asset. The user receives a quantity of cTokens equal to the
    /// underlying tokens supplied, divided by the current Exchange Rate.
    /// @param mintAmount The amount of the asset to be supplied, in units of the underlying asset.
    /// @return 0 on success, otherwise an Error code
    function mint(uint256 mintAmount) external returns (uint256);

    /// The redeem function converts a specified quantity of cTokens into the underlying asset, and returns
    /// them to the user. The amount of underlying tokens received is equal to the quantity of cTokens redeemed,
    /// multiplied by the current Exchange Rate. The amount redeemed must be less than the user's Account Liquidity
    /// and the market's available liquidity.
    /// @param redeemTokens The number of cTokens to be redeemed.
    /// @return 0 on success, otherwise an Error code
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface CETHTokenInterface {
    ///@notice Send Ether to CEther to mint
    function mint() external payable;
}

interface ComptrollerInterface {
    /// @notice Claim all the comp accrued by holder in all markets
    /// @param holder The address to claim COMP for
    function claimComp(address holder) external;
}

interface PriceOracleInterface {
    /// @notice Get the price of an underlying asset.
    /// @param underlying The underlying asset to get the price of.
    /// @return The underlying asset price in ETH as a mantissa (scaled by 1e18).
    /// Zero means the price is unavailable.
    function price(address underlying) external view returns (uint256);
}

/// @notice Adapter contract for cTokens
contract CAdapter is CropAdapter {
    using FixedMath for uint256;
    using SafeERC20 for ERC20;

    address public constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public override underlying;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint48 _minm,
        uint48 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level,
        address _reward
    ) CropAdapter(_divider, _target, _oracle, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _tilt, _level, _reward) {
        // Approve underlying contract to pull target (used on wrapUnderlying())
        underlying = _isCETH(_target) ? WETH : CTokenInterface(_target).underlying();
        ERC20(underlying).safeApprove(_target, type(uint256).max);
    }

    /// @return Exchange rate from Target to Underlying using Compound's `exchangeRateCurrent()`, normed to 18 decimals
    function scale() external override returns (uint256) {
        uint256 uDecimals = CTokenInterface(underlying).decimals();
        uint256 exRate = CTokenInterface(target).exchangeRateCurrent();
        // From the Compound docs:
        // "exchangeRateCurrent() returns the exchange rate, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals)"
        //
        // The equation to norm an asset to 18 decimals is:
        // `num * 10**(18 - decimals)`
        //
        // So, when we try to norm exRate to 18 decimals, we get the following:
        // `exRate * 10**(18 - exRateDecimals)`
        // -> `exRate * 10**(18 - (18 - 8 + uDecimals))`
        // -> `exRate * 10**(8 - uDecimals)`
        // -> `exRate / 10**(uDecimals - 8)`
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    function scaleStored() external view override returns (uint256) {
        uint256 uDecimals = CTokenInterface(underlying).decimals();
        uint256 exRate = CTokenInterface(target).exchangeRateStored();
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return _isCETH(target) ? 1e18 : PriceOracleInterface(oracle).price(underlying);
    }

    function wrapUnderlying(uint256 uBal) external override returns (uint256) {
        bool isCETH = _isCETH(target);
        ERC20 u = ERC20(underlying);
        ERC20 target = ERC20(target);

        u.safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        if (isCETH) IWETH(WETH).withdraw(uBal); // unwrap WETH into ETH

        // mint target
        uint256 tBalBefore = target.balanceOf(address(this));
        if (isCETH) {
            CETHTokenInterface(address(target)).mint{ value: uBal }();
        } else {
            require(CTokenInterface(address(target)).mint(uBal) == 0, "Mint failed");
        }
        uint256 tBalAfter = target.balanceOf(address(this));
        uint256 tBal = tBalAfter - tBalBefore;

        // transfer target to sender
        ERC20(target).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    function unwrapTarget(uint256 tBal) external override returns (uint256) {
        ERC20 u = ERC20(underlying);
        bool isCETH = _isCETH(address(target));
        ERC20 target = ERC20(target);
        target.safeTransferFrom(msg.sender, address(this), tBal); // pull target

        // redeem target for underlying
        uint256 uBalBefore = isCETH ? address(this).balance : u.balanceOf(address(this));
        require(CTokenInterface(address(target)).redeem(tBal) == 0, "Redeem failed");
        uint256 uBalAfter = isCETH ? address(this).balance : u.balanceOf(address(this));
        uint256 uBal = uBalAfter - uBalBefore;

        if (isCETH) {
            // deposit ETH into WETH contract
            (bool success, ) = WETH.call{ value: uBal }("");
            require(success, "Transfer failed.");
        }

        // transfer underlying to sender
        u.safeTransfer(msg.sender, uBal);
        return uBal;
    }

    function _isCETH(address target) internal view returns (bool) {
        return keccak256(abi.encodePacked(ERC20(target).symbol())) == keccak256(abi.encodePacked("cETH"));
    }

    fallback() external payable {}
}
