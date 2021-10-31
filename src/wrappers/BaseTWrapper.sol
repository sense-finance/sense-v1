// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";
import { FixedMath } from "../external/FixedMath.sol";

// Internal
import { Periphery } from "../Periphery.sol";
import { Divider } from "../Divider.sol";
import { BaseFeed as Feed } from "../feeds/BaseFeed.sol";
import { Errors } from "../libs/Errors.sol";

/// @notice Accumulate reward tokens and distribute them proportionally
/// Inspired by: https://github.com/makerdao/dss-crop-join
abstract contract BaseTWrapper is Initializable {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Program state
    address public divider;
    address public target;
    address public stake;
    address public reward;
    uint256 public share; // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget;
    mapping(address => uint256) public tBalance;
    mapping(address => uint256) public rewarded; // reward token per collected target per user

    function initialize(
        address _divider,
        address _target,
        address _stake,
        address _reward
    ) external virtual initializer {
        divider = _divider;
        target = _target;
        stake = _stake;
        reward = _reward;
        ERC20(target).approve(_divider, type(uint256).max);
        ERC20(stake).approve(_divider, type(uint256).max);

        emit Initialized();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function join(address _usr, uint256 val) public onlyDivider {
        _distribute(_usr);
        if (val > 0) {
            totalTarget += val;
            tBalance[_usr] += val;
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(share, FixedMath.RAY);
    }

    function exit(address _usr, uint256 val) public onlyDivider {
        _distribute(_usr);
        if (val > 0) {
            totalTarget -= val;
            tBalance[_usr] -= val;
        }
        rewarded[_usr] = tBalance[_usr].fmulUp(share, FixedMath.RAY);
    }

    /// @notice Loan `amount` target to `receiver`, and takes it back after the callback.
    /// @param receiver The contract receiving target, needs to implement the
    /// `onFlashLoan(address user, address feed, uint256 maturity, uint256 amount)` interface.
    /// @param feed feed address
    /// @param maturity maturity
    /// @param amount The amount of target lent.
    function flashLoan(
        bytes calldata data,
        address receiver,
        address feed,
        uint256 maturity,
        uint256 amount
    ) external onlyPeriphery returns (bool, uint256) {
        require(ERC20(target).transfer(address(receiver), amount), Errors.FlashTransferFailed);
        (bytes32 keccak, uint256 value) = Periphery(receiver).onFlashLoan(data, msg.sender, feed, maturity, amount);
        require(keccak == CALLBACK_SUCCESS, Errors.FlashCallbackFailed);
        require(ERC20(target).transferFrom(address(receiver), address(this), amount), Errors.FlashRepayFailed);
        return (true, value);
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

    /// @notice Deposits underlying `amount`in return for target. Must be overriden by child contracts.
    /// @param amount Underlying amount
    /// @return amount of target returned
    function wrapUnderlying(uint256 amount) external virtual returns (uint256);

    /// @notice Deposits target `amount`in return for underlying. Must be overriden by child contracts.
    /// @param amount Target amount
    /// @return amount of underlying returned
    function unwrapTarget(uint256 amount) external virtual returns (uint256);

    /* ========== MODIFIERS ========== */
    modifier onlyDivider() {
        require(divider == msg.sender, "Can only be invoked by the Divider contract");
        _;
    }

    modifier onlyPeriphery() {
        require(Divider(divider).periphery() == msg.sender, Errors.OnlyPeriphery);
        _;
    }

    /* ========== EVENTS ========== */
    event Distributed(address indexed usr, address indexed token, uint256 amount);
    event Initialized();
}
