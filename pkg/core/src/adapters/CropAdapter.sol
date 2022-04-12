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

abstract contract CropAdapter is Trust, BaseAdapter {
    using SafeTransferLib for ERC20;
    using FixedMath for uint256;

    /// @notice Program state
    uint256 public totalTarget;
    mapping(address => uint256) public tBalance;

    address[] public rewardTokens;
    mapping(address => uint256) public shares; // accumulated reward token per collected target per reward token
    mapping(address => uint256) public rewardedBalances; // last recorded balance of reward token per reward token
    mapping(address => mapping(address => uint256)) public rewarded; // rewarded token per token per user
    // TODO: simplify mappings into only one as they share the same key?

    event Distributed(address indexed usr, address indexed token, uint256 amount);

    constructor(
        address _divider,
        BaseAdapter.AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) Trust(msg.sender) BaseAdapter(_divider, _adapterParams) {
        rewardTokens = _rewardTokens;
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

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            rewarded[rewardTokens[i]][_usr] = tBalance[_usr].fmulUp(shares[rewardTokens[i]], FixedMath.RAY);
        }
    }

    /// @notice Distributes rewarded tokens to users proportionally based on their `tBalance`
    /// @param _usr User to distribute reward tokens to
    function _distribute(address _usr) internal {
        _claimRewards();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 crop = ERC20(rewardTokens[i]).balanceOf(address(this)) - rewardedBalances[rewardTokens[i]];
            if (totalTarget > 0) shares[rewardTokens[i]] += (crop.fdiv(totalTarget, FixedMath.RAY));

            uint256 last = rewarded[rewardTokens[i]][_usr];
            uint256 curr = tBalance[_usr].fmul(shares[rewardTokens[i]], FixedMath.RAY);
            if (curr > last) {
                unchecked {
                    ERC20(rewardTokens[i]).safeTransfer(_usr, curr - last);
                }
            }
            rewardedBalances[rewardTokens[i]] = ERC20(rewardTokens[i]).balanceOf(address(this));
            emit Distributed(_usr, rewardTokens[i], curr > last ? curr - last : 0);
        }
    }

    /// @notice Some protocols don't airdrop reward tokens, instead users must claim them.
    /// This method may be overriden by child contracts to claim a protocol's rewards
    function _claimRewards() internal virtual {
        return;
    }

    function setRewardTokens(address[] memory _rewardTokens) public requiresTrust {
        _claimRewards();
        rewardTokens = _rewardTokens;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyDivider() {
        if (divider != msg.sender) revert Errors.OnlyDivider();
        _;
    }
}
