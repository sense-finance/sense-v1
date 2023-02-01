// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// External references
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { IClaimer } from "../IClaimer.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Trust } from "@sense-finance/v1-utils/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

/// @notice This is meant to be used with BaseAdapter.sol
abstract contract Crop is Trust {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    address public claimer; // claimer address
    address public reward;
    uint256 public shares; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget; // total target accumulated by all users
    mapping(address => uint256) public tBalance; // target balance per user
    mapping(address => uint256) public rewarded; // reward token per user
    mapping(address => uint256) public reconciledAmt; // reconciled target amount per user
    mapping(address => mapping(uint256 => bool)) public reconciled; // whether a user has been reconciled for a given maturity

    constructor(address _divider, address _reward) {
        setIsTrusted(_divider, true);
        reward = _reward;
    }

    /// @notice Distribute the rewards tokens to the user according to their shares
    /// @dev The reconcile amount allows us to prevent diluting other users' rewards
    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public virtual requiresTrust {
        _distribute(_usr);
        if (amt > 0) {
            if (join) {
                totalTarget += amt;
                tBalance[_usr] += amt;
            } else {
                uint256 uReconciledAmt = reconciledAmt[_usr];
                if (uReconciledAmt > 0) {
                    if (amt < uReconciledAmt) {
                        unchecked {
                            uReconciledAmt -= amt;
                        }
                        amt = 0;
                    } else {
                        unchecked {
                            amt -= uReconciledAmt;
                        }
                        uReconciledAmt = 0;
                    }
                    reconciledAmt[_usr] = uReconciledAmt;
                }
                if (amt > 0) {
                    totalTarget -= amt;
                    tBalance[_usr] -= amt;
                }
            }
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(shares, FixedMath.RAY);
    }

    /// @notice Reconciles users target balances to zero by distributing rewards on their holdings,
    /// to avoid dilution of next Series' YT holders.
    /// This function should be called right after a Series matures and will save the user's YT balance
    /// (in target terms) on reconciledAmt[usr]. When `notify()` is triggered, we take that amount and
    /// subtract it from the user's target balance (`tBalance`) which will fix (or reconcile)
    /// his position to prevent dilution.
    /// @param _usrs Users to reconcile
    /// @param _maturities Maturities of the series that we want to reconcile users on.
    function reconcile(address[] calldata _usrs, uint256[] calldata _maturities) public {
        Divider divider = Divider(BaseAdapter(address(this)).divider());
        for (uint256 j = 0; j < _maturities.length; j++) {
            for (uint256 i = 0; i < _usrs.length; i++) {
                address usr = _usrs[i];
                uint256 ytBal = ERC20(divider.yt(address(this), _maturities[j])).balanceOf(usr);
                // We don't want to reconcile users if maturity has not been reached or if they have already been reconciled
                if (_maturities[j] <= block.timestamp && ytBal > 0 && !reconciled[usr][_maturities[j]]) {
                    _distribute(usr);
                    uint256 tBal = ytBal.fdiv(divider.lscales(address(this), _maturities[j], usr));
                    totalTarget -= tBal;
                    tBalance[usr] -= tBal;
                    reconciledAmt[usr] += tBal; // We increase reconciledAmt with the user's YT balance in target terms
                    reconciled[usr][_maturities[j]] = true;
                    emit Reconciled(usr, tBal, _maturities[j]);
                }
            }
        }
    }

    /// @notice Distributes rewarded tokens to users proportionally based on their `tBalance`
    /// @param _usr User to distribute reward tokens to
    function _distribute(address _usr) internal {
        _claimReward();

        uint256 crop = ERC20(reward).balanceOf(address(this)) - rewardBal;
        if (totalTarget > 0) shares += (crop.fdiv(totalTarget, FixedMath.RAY));

        uint256 last = rewarded[_usr];
        uint256 curr = tBalance[_usr].fmul(shares, FixedMath.RAY);
        if (curr > last) {
            unchecked {
                ERC20(reward).safeTransfer(_usr, curr - last);
            }
        }
        rewardBal = ERC20(reward).balanceOf(address(this));
        emit Distributed(_usr, reward, curr > last ? curr - last : 0);
    }

    /// @notice Some protocols don't airdrop reward tokens, instead users must claim them.
    /// This method may be overriden by child contracts to claim a protocol's rewards
    function _claimReward() internal virtual {
        if (claimer != address(0)) {
            ERC20 target = ERC20(BaseAdapter(address(this)).target());
            uint256 tBal = ERC20(target).balanceOf(address(this));

            if (tBal > 0) {
                // We send all the target balance to the claimer contract to it can claim rewards
                ERC20(target).transfer(claimer, tBal);

                // Make claimer to claim rewards
                IClaimer(claimer).claim();

                // Get the target back
                if (ERC20(target).balanceOf(address(this)) < tBal) revert Errors.BadContractInteration();
            }
        }
    }

    /// @notice Overrides the rewardToken address.
    /// @param _reward New reward token address
    function setRewardToken(address _reward) public requiresTrust {
        _claimReward();
        reward = _reward;
        emit RewardTokenChanged(reward);
    }

    /// @notice Sets `claimer`.
    /// @param _claimer New claimer contract address
    function setClaimer(address _claimer) public requiresTrust {
        claimer = _claimer;
        emit ClaimerChanged(claimer);
    }

    /* ========== LOGS ========== */

    event Distributed(address indexed usr, address indexed token, uint256 amount);
    event Reconciled(address indexed usr, uint256 tBal, uint256 maturity);
    event RewardTokenChanged(address indexed reward);
    event ClaimerChanged(address indexed claimer);
}
