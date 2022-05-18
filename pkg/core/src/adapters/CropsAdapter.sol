// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider } from "../Divider.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";

abstract contract CropsAdapter is Trust, BaseAdapter {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    uint256 public totalTarget; // total target accumulated by all users
    mapping(address => uint256) public tBalance; // target balance per user
    mapping(address => uint256) public reconciledAmt; // reconciled target amount per user
    mapping(address => mapping(uint256 => bool)) public reconciled; // whether a user has been reconciled for a given maturity

    address[] public rewardTokens; // reward tokens addresses
    mapping(address => Crop) public data;

    struct Crop {
        // Accumulated reward token per collected target
        uint256 shares;
        // Last recorded balance of this contract per reward token
        uint256 rewardedBalances;
        // Rewarded token per token per user
        mapping(address => uint256) rewarded;
    }

    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) Trust(msg.sender) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {
        rewardTokens = _rewardTokens;
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override {
        if (reconciledAmt[_usr] > 0) {
            if (!join) {
                if (amt < reconciledAmt[_usr]) {
                    reconciledAmt[_usr] -= amt;
                    amt = 0;
                } else {
                    amt -= reconciledAmt[_usr];
                    reconciledAmt[_usr] = 0;
                }
            }
        }

        if (divider != msg.sender) revert Errors.OnlyDivider();
        _distribute(_usr);
        if (amt > 0) {
            if (join) {
                totalTarget += amt;
                tBalance[_usr] += amt;
            } else {
                totalTarget -= amt;
                tBalance[_usr] -= amt;
            }
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            data[rewardTokens[i]].rewarded[_usr] = tBalance[_usr].fmulUp(data[rewardTokens[i]].shares, FixedMath.RAY);
        }
    }

    /// @notice Reconciles users target balances to avoid delution of next Series YT holders.
    /// This function should be called right after a Series matures.
    /// @param _usrs Users to reconcile
    /// @param _maturities Maturities of the series that we want to reconcile users on.
    function reconcile(address[] calldata _usrs, uint256[] calldata _maturities) public {
        for (uint256 i = 0; i < _usrs.length; i++) {
            address usr = _usrs[i];
            for (uint256 j = 0; j < _maturities.length; j++) {
                (, , address yt, , , , , uint256 mscale, ) = Divider(divider).series(address(this), _maturities[j]);
                if (
                    _maturities[j] < block.timestamp && ERC20(yt).balanceOf(usr) > 0 && !reconciled[usr][_maturities[j]]
                ) {
                    _distribute(usr);
                    uint256 tBal = ERC20(yt).balanceOf(usr).fdiv(mscale);
                    totalTarget -= tBal;
                    tBalance[usr] -= tBal;
                    reconciledAmt[usr] += tBal;
                    reconciled[usr][_maturities[j]] = true;
                    emit Reconciled(usr);
                }
            }
        }
    }

    /// @notice Distributes rewarded tokens to users proportionally based on their `tBalance`
    /// @param _usr User to distribute reward tokens to
    function _distribute(address _usr) internal {
        _claimRewards();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 crop = ERC20(rewardTokens[i]).balanceOf(address(this)) - data[rewardTokens[i]].rewardedBalances;
            if (totalTarget > 0) data[rewardTokens[i]].shares += (crop.fdiv(totalTarget, FixedMath.RAY));

            uint256 last = data[rewardTokens[i]].rewarded[_usr];
            uint256 curr = tBalance[_usr].fmul(data[rewardTokens[i]].shares, FixedMath.RAY);
            if (curr > last) {
                unchecked {
                    ERC20(rewardTokens[i]).safeTransfer(_usr, curr - last);
                }
            }
            data[rewardTokens[i]].rewardedBalances = ERC20(rewardTokens[i]).balanceOf(address(this));
            emit Distributed(_usr, rewardTokens[i], curr > last ? curr - last : 0);
        }
    }

    /// @notice Some protocols don't airdrop reward tokens, instead users must claim them.
    /// This method may be overriden by child contracts to claim a protocol's rewards
    function _claimRewards() internal virtual {
        return;
    }

    /// @notice Overrides the rewardTokens array with a new one.
    /// @dev Calls _claimRewards() in case the new array contains less reward tokens than the old one.
    /// @param _rewardTokens New reward tokens array
    function setRewardTokens(address[] memory _rewardTokens) public requiresTrust {
        _claimRewards();
        rewardTokens = _rewardTokens;
        emit RewardTokensChanged(rewardTokens);
    }

    /* ========== LOGS ========== */

    event Distributed(address indexed usr, address indexed token, uint256 amount);
    event RewardTokensChanged(address[] indexed rewardTokens);
    event Reconciled(address indexed usr);
}
