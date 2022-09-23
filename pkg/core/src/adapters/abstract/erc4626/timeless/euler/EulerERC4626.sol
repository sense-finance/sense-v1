// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.11;

import { ExtractableReward } from "../base/ExtractableReward.sol";

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

import { IEulerEToken } from "./external/IEulerEToken.sol";

/// @title EulerERC4626
/// @author forked from Yield Daddy (Timeless Finance)
/// @notice ERC4626 wrapper for Euler Finance
contract EulerERC4626 is ERC4626, ExtractableReward {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice The Euler main contract address
    /// @dev Target of ERC20 approval when depositing
    address public immutable euler;

    /// @notice The Euler eToken contract
    IEulerEToken public immutable eToken;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 _asset,
        address _euler,
        IEulerEToken _eToken,
        address _rewardsRecipient
    ) ERC4626(_asset, _vaultName(_asset), _vaultSymbol(_asset)) ExtractableReward(_rewardsRecipient) {
        euler = _euler;
        eToken = _eToken;
        rewardsRecipient = _rewardsRecipient;
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return eToken.balanceOfUnderlying(address(this));
    }

    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Euler
        /// -----------------------------------------------------------------------

        eToken.withdraw(0, assets);
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Euler
        /// -----------------------------------------------------------------------

        // approve to euler
        asset.safeApprove(address(euler), assets);

        // deposit into eToken
        eToken.deposit(0, assets);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = asset.balanceOf(euler);
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = asset.balanceOf(euler);
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 _asset) internal view virtual returns (string memory vaultName) {
        vaultName = string(abi.encodePacked("ERC4626-Wrapped Euler ", _asset.symbol()));
    }

    function _vaultSymbol(ERC20 _asset) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string(abi.encodePacked("we", _asset.symbol()));
    }

    /// -----------------------------------------------------------------------
    /// Overrides
    /// -----------------------------------------------------------------------
    function _isValid(address _token) internal override returns (bool) {
        return _token != address(eToken);
    }
}
