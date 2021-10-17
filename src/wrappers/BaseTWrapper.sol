// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "solmate/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";

/// @notice
contract BaseTWrapper is Initializable {
    using FixedMath for uint256;
    /// @notice Configuration

    /// @notice Mutable program state
    address public target;
    address public reward;
    address public divider;
    uint256 totalClaims;
    mapping(address => uint256) claimBalance;

    function initialize(
        address _target,
        address _divider,
        address _reward
    ) external virtual initializer {
        target = _target;
        divider = _divider;
        reward = _reward;
        ERC20(target).approve(divider, 2**256 - 1); // approve max int
        emit Initialized();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    uint256 public share; // accumulated reward token per collected target
    uint256 public totalCollected; // total target collected
    uint256 public lastRewardBal; // last recorded balance of reward token

    mapping(address => uint256) public crops; // reward token per collected target per user
    mapping(address => uint256) public collected; // collected target per user

    function crop() internal virtual returns (uint256) {
        return ERC20(reward).balanceOf(address(this)) - lastRewardBal;
    }

    /// @notice Distributes rewarded tokens to Claim holders proportionally based on Claim balance
    /// @param _feed Feed to associate with the Series
    /// @param _maturity Maturity date
    /// @param _usr User to distribute reward tokens to
    function distribute(
        address _feed,
        uint256 _maturity,
        address _usr
    ) external {
        _claimReward();
        if (totalClaims > 0) share += (crop().fdiv(totalClaims, 10**27)); // TODO: fdiv()?
        uint256 last = crops[_usr];
        uint256 curr = claimBalance[_usr].fmul(share, 10**27); // TODO: fmul()?
        if (curr > last) require(ERC20(reward).transfer(_usr, curr - last));
        lastRewardBal = ERC20(reward).balanceOf(address(this));

        (, address claim, , , , , , ,) = Divider(divider).series(_feed, _maturity);
        crops[_usr] = ERC20(claim).balanceOf(_usr).fmulUp(share, 10**27); // TODO: fmulup()?
        totalClaims = ERC20(claim).totalSupply();
        claimBalance[_usr] = ERC20(claim).balanceOf(_usr);
    }

    /// @notice Some protocols do not airdrop the reward token but the user needs to amake a call to claim them.
    /// If so, must be overriden by child contracts
    function _claimReward() internal virtual {
        return;
    }

    /* ========== EVENTS ========== */
    event Distributed(address indexed usr, address indexed token, uint256 indexed amount);
    event Initialized();
}
