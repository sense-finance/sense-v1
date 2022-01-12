// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

// External references
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { Divider } from "../Divider.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Trust } from "@sense-finance/v1-utils/src/Trust.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";

abstract contract CropAdapter is BaseAdapter {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    address public immutable reward;
    uint256 public share; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget;
    mapping(address => uint256) public tBalance;
    mapping(address => uint256) public rewarded; // reward token per user

    event Distributed(address indexed usr, address indexed token, uint256 amount);

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level,
        address _reward
    ) BaseAdapter(_divider, _target, _oracle, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _tilt, _level) {
        reward = _reward;
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override onlyDivider {
        _distribute(_usr);
        if (amt > 0) {
            if (join) {
                totalTarget += amt;
                tBalance[_usr] += amt;
            } else {
                // else `exit`
                totalTarget -= amt;
                tBalance[_usr] -= amt;
            }
        }

        rewarded[_usr] = tBalance[_usr].fmulUp(share, FixedMath.RAY);
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
    /// This method may be overriden by child contracts to Claim a protocol's rewards
    function _claimReward() internal virtual {
        return;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyDivider() {
        require(divider == msg.sender, Errors.OnlyDivider);
        _;
    }
}
