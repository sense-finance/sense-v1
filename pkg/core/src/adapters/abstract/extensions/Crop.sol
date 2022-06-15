// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Divider } from "../../../Divider.sol";
import { BaseAdapter } from "../BaseAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

abstract contract Crop is Trust {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    address public immutable reward;
    uint256 public share; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget; // total target accumulated by all users
    mapping(address => uint256) public tBalance; // target balance per user
    mapping(address => uint256) public rewarded; // reward token per user
    mapping(address => uint256) public reconciledAmt; // reconciled target amount per user
    mapping(address => mapping(uint256 => bool)) public reconciled; // whether a user has been reconciled for a given maturity

    event Distributed(address indexed usr, address indexed token, uint256 amount);

    constructor(address _divider, address _reward) Trust(_divider) {
        reward = _reward;
    }

    // What is reconciled amount? It is a user's YT balance in target terms of a matured Series
    // that it should have been decremented from the `tBalance` but it was not because the user
    // did not redeemed their YTs (yet).
    // Note that, when reconciliing, the user receives the corresponding rewards until maturity.
    // The `reconciledAmt` allows us to prevent diluting other user's future Series rewards because
    // we can keep track of those amounts and subtract them from the `tBalance` when needed.
    // Reconciled amounts can be thought as a debt on the `tBalance` that the user will repay
    // when issuing (join = true)

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public virtual requiresTrust {
        _distribute(_usr);
        emit Log(tBalance[_usr]);
        emit Log(amt);
        if (amt > 0) {
            uint256 uReconciledAmt = reconciledAmt[_usr];
            emit Log(uReconciledAmt);
            if (join) {
                // if user has debt (`reconciledAmt` > 0) we use the `amt` to pay it off (partially
                // or completely, dependening on the case)
                // but, note that the `amt` var is not modified because the user needs to have his `tBalance`
                // incremented by the total amount that he has deposited
                // otherwise, if we would be decrementing `amt`, when doing tBalance[_usr] += amt
                // tBalance would be incremented with less amount which will result in the user having
                // a smaller share
                // why do we need to keep track of the `reconciledAmt`? `reconciledAmt` is does not really affects
                // the joins but it is the place where we can know when the user pays it off.
                // The `reconciledAmt` has its use when redeeming/combining (see comments on the `else` condition)
                // IMPORTANT: one might want to think that the `reconciledAmt` + `tBalance` = `totalTarget`
                // (amount of target deposited by users across all Series). But this is not the case because when
                // user issues and has a `reconciledAmt`, we always increment his `tBalance` but we decrease his `reconciledAmt`:
                // e.g Alice issues 10 on S1 ->     tBalance = 10, reconciledAmt = 0,  totalTarget = 10
                //     Alice is reconciled   ->     tBalance = 0,  reconciledAmt = 10, totalTarget = 0
                //     Alice issues 10 on S2 ->     tBalance = 10, reconciledAmt = 0,  totalTarget = 10 IMBALANCE
                // note how `totalTarget` is 10 though the user has 20 target (10 from S1 and 10 from S2)
                // let's call `extraTarget` to the difference between current `totalTarget` and the total
                // amount of target the user has deposited (in other words, the current YT balance across all Series
                // in target terms)

                if (uReconciledAmt > 0) {
                    // and is greater than the target the user is issuing (aka `amt`)
                    // we partially pay the debt (aka `reconciledAmt`) off
                    if (uReconciledAmt > amt) {
                        unchecked {
                            uReconciledAmt -= amt;
                        }
                        // we completely settle the debt (that's why we set the `reconciledAmt` to 0)
                    } else {
                        uReconciledAmt = 0;
                    }

                    // QUESTION; does it matter that with this mechanism, by issuing on Series 2, we could be
                    // paying the debt (decreasing `reconciledAmt`) generated on a previous Series (e.g Series 1)?
                    // I think it does not matter because... (FILL IN WIHT A BETTERR EXPLANATION)

                    // TODO: check what happens when late reconcile
                    // TODO: check what happens when scale changes
                }
                // no matter if a user had debt or not, we always add the target amount (`amt`) to the `tBalance`
                // when issuing
                totalTarget += amt;
                tBalance[_usr] += amt;
            } else {
                // when a user redeems/combines we decrement the user's targetBalance by the `amt` being
                // redeemed/combined but
                if (uReconciledAmt > 0) {
                    if (uReconciledAmt <= amt) {
                        // if debt is smaller than `amt` being redeemed/combined, we can just settle it
                        // because... ELABORATE
                        uReconciledAmt = 0;
                    } else {
                        uReconciledAmt -= amt;
                    }
                }
                // because of the imbalance generated with the `extraTarget`, when user redeem/combines
                // it might happen that the `amt` redeemed/combined is greater than the user's `tBalance`
                // so we skip from decrementing because there's actually no need to do that
                // FIXME: this is wrong because if a user combines/redeems new YTs before having
                // combined/redeemed his old YTs his `tBalance` will be decremented which will dilute his
                // own share. WE HAVE NO WAY OF BEING ABLE TO KNOW WHEN  WE CAN OR CAN NOT DECREMENT `tBalance`
                // because we are missisng the maturity.
                if (tBalance[_usr] >= amt) {
                    totalTarget -= amt;
                    tBalance[_usr] -= amt;
                }
            }
            reconciledAmt[_usr] = uReconciledAmt;
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(share, FixedMath.RAY);
    }

    event Log(uint256);

    /// @notice Reconciles users target balances to zero by distributing rewards on their holdings,
    /// to avoid dilution of next Series' YT holders.
    /// This function should be called right after a Series matures and will save the user's YT balance
    /// (in target terms) on reconciledAmt[usr]. When `notify()` is triggered for on a new Series, we will
    /// take that amount and subtract it from the user's target balance (`tBalance`) which will fix (or reconcile)
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
        if (totalTarget > 0) share += (crop.fdiv(totalTarget, FixedMath.RAY));

        uint256 last = rewarded[_usr];
        uint256 curr = tBalance[_usr].fmul(share, FixedMath.RAY);
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
        return;
    }

    /* ========== LOGS ========== */

    event Reconciled(address indexed usr, uint256 tBal, uint256 maturity);
    
}
