// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

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

    function initialize(
        address _divider,
        AdapterParams memory _adapterParams,
        address _reward
    ) public virtual override initializer {
        // approve underlying contract to pull target (used on wrapUnderlying())
        address target = _adapterParams.target;
        ERC20 u = ERC20(_isCETH(target) ? WETH : CTokenInterface(target).underlying());
        u.safeApprove(_adapterParams.target, type(uint256).max);
        super.initialize(_divider, _adapterParams, _reward);
    }

    /// @return Exchange rate from Target to Underlying using Compound's `exchangeRateCurrent()`, normed to 18 decimals
    function scale() external override returns (uint256) {
        uint256 uDecimals = CTokenInterface(underlying()).decimals();
        uint256 exRate = CTokenInterface(adapterParams.target).exchangeRateCurrent();
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    function scaleStored() external view override returns (uint256) {
        uint256 uDecimals = CTokenInterface(underlying()).decimals();
        uint256 exRate = CTokenInterface(adapterParams.target).exchangeRateStored();
        return uDecimals >= 8 ? exRate / 10**(uDecimals - 8) : exRate * 10**(8 - uDecimals);
    }

    function _claimReward() internal virtual override {
        ComptrollerInterface(COMPTROLLER).claimComp(address(this));
    }

    function underlying() public view override returns (address) {
        address target = adapterParams.target;
        return _isCETH(target) ? WETH : CTokenInterface(target).underlying();
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        address target = adapterParams.target;
        return
            _isCETH(target)
                ? 1e18
                : PriceOracleInterface(adapterParams.oracle).price(CTokenInterface(target).underlying());
    }

    function wrapUnderlying(uint256 uBal) external override returns (uint256) {
        ERC20 u = ERC20(underlying());
        ERC20 target = ERC20(adapterParams.target);
        bool isCETH = _isCETH(address(adapterParams.target));

        u.safeTransferFrom(msg.sender, address(this), uBal); // pull underlying
        if (isCETH) IWETH(WETH).withdraw(uBal); // unwrap WETH into ETH

        // mint target
        uint256 tBalBefore = target.balanceOf(address(this));
        if (isCETH) {
            CETHTokenInterface(adapterParams.target).mint{ value: uBal }();
        } else {
            require(CTokenInterface(adapterParams.target).mint(uBal) == 0, "Mint failed");
        }
        uint256 tBalAfter = target.balanceOf(address(this));
        uint256 tBal = tBalAfter - tBalBefore;

        // transfer target to sender
        ERC20(target).safeTransfer(msg.sender, tBal);
        return tBal;
    }

    function unwrapTarget(uint256 tBal) external override returns (uint256) {
        ERC20 u = ERC20(underlying());
        bool isCETH = _isCETH(address(adapterParams.target));
        ERC20 target = ERC20(adapterParams.target);
        target.safeTransferFrom(msg.sender, address(this), tBal); // pull target

        // redeem target for underlying
        uint256 uBalBefore = isCETH ? address(this).balance : u.balanceOf(address(this));
        require(CTokenInterface(adapterParams.target).redeem(tBal) == 0, "Redeem failed");
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
