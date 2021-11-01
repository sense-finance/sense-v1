// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { Divider } from "../Divider.sol";
import { BaseAdapter } from "./BaseAdapter.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Errors } from "../libs/Errors.sol";

abstract contract CropAdapter is BaseAdapter {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    address public reward;
    uint256 public share; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget;
    mapping(address => uint256) public tBalance;
    mapping(address => uint256) public rewarded; // reward token per collected target per user

    event Distributed(address indexed usr, address indexed token, uint256 amount);

    function initialize(
        address _divider,
        AdapterParams memory _adapterParams,
        address _reward
    ) public {
        super.initialize(_divider, _adapterParams);
        reward = _reward;
        ERC20(_adapterParams.stake).safeApprove(_divider, type(uint256).max);
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
        if (curr > last) ERC20(reward).safeTransfer(_usr, curr - last);
        rewardBal = ERC20(reward).balanceOf(address(this));
        emit Distributed(_usr, reward, curr > last ? curr - last : 0);
    }

    /// @notice Some protocols don't airdrop reward tokens, instead users must claim them –
    /// this method may be overriden by child contracts to Claim a protocol's rewards
    function _claimReward() internal virtual {
        return;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyDivider() {
        require(divider == msg.sender, Errors.OnlyDivider);
        _;
    }
}
