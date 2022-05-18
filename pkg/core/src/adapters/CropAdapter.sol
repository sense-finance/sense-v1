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

abstract contract CropAdapter is BaseAdapter {
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

    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        BaseAdapter.AdapterParams memory _adapterParams,
        address _reward
    ) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {
        reward = _reward;
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override onlyDivider {
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
        rewarded[_usr] = tBalance[_usr].fmulUp(share, FixedMath.RAY);
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

    /* ========== MODIFIERS ========== */

    modifier onlyDivider() {
        if (divider != msg.sender) revert Errors.OnlyDivider();
        _;
    }

    /* ========== LOGS ========== */

    event Reconciled(address indexed usr);
}
