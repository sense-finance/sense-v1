// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "solmate/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Trust } from "solmate/auth/Trust.sol";

// Internal
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";

/// @notice
contract BaseTWrapper is Initializable {
    using FixedMath for uint256;

    /// @notice Program state
    address public target;
    address public divider;
    address public reward;
    uint256 public share; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 totalTarget;
    mapping(address => uint256) tBalance;
    mapping(address => uint256) public rewarded; // reward token per collected target per user

    function initialize(
        address _target,
        address _divider,
        address _reward
    ) external virtual initializer {
        target = _target;
        divider = _divider;
        reward = _reward;
        ERC20(target).approve(divider, type(uint256).max); // approve max int
        emit Initialized();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function join(
        address _feed,
        uint256 _maturity,
        address _usr,
        uint256 val
    ) public onlyDivider {
        _distribute(_feed, _maturity, _usr);
        (, address claim, , , , , , , ) = Divider(divider).series(_feed, _maturity);
        if (val > 0) {
            totalTarget += val;
            tBalance[_usr] += val;
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(share, 10**27);
    }

    function exit(
        address _feed,
        uint256 _maturity,
        address _usr,
        uint256 val
    ) public onlyDivider {
        _distribute(_feed, _maturity, _usr);
        (, address claim, , , , , , , ) = Divider(divider).series(_feed, _maturity);
        if (val > 0) {
            totalTarget -= val;
            tBalance[_usr] -= val;
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(share, 10**27);
    }

    /// @notice Distributes rewarded tokens to Claim holders proportionally based on Claim balance
    /// @param _feed Feed to associate with the Series
    /// @param _maturity Maturity date
    /// @param _usr User to distribute reward tokens to
    function _distribute(
        address _feed,
        uint256 _maturity,
        address _usr
    ) internal {
        _claimReward();
        uint256 crop = ERC20(reward).balanceOf(address(this)) - rewardBal;
        if (totalTarget > 0) share += (crop().fdiv(totalTarget, 10**27));
        uint256 last = rewarded[_usr];
        uint256 curr = tBalance[_usr].fmul(share, 10**27);
        if (curr > last) require(ERC20(reward).transfer(_usr, curr - last));
        rewardBal = ERC20(reward).balanceOf(address(this));
        emit Distributed(_usr, reward, curr > last ? curr - last : 0);
    }

    /// @notice Some protocols do not airdrop the reward token but the user needs to make a call to claim them.
    /// If so, must be overriden by child contracts
    function _claimReward() internal virtual {
        return;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyDivider() {
        require(divider == msg.sender, "Can only be invoked by the Divider contract");
        _;
    }

    /* ========== EVENTS ========== */
    event Distributed(address indexed usr, address indexed token, uint256 indexed amount);
    event Initialized();
}
