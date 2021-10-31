// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

// External references
import { Trust } from "@rari-capital/solmate/src/auth/Trust.sol";
import { ERC20, SafeERC20 } from "@rari-capital/solmate/src/erc20/SafeERC20.sol";

// Internal references
import { Periphery } from "../Periphery.sol";
import { BaseFeed } from "./BaseFeed.sol";
import { FixedMath } from "../external/FixedMath.sol";
import { Errors } from "../libs/Errors.sol";

abstract contract CropFeed is BaseFeed, Trust {
    using SafeERC20 for ERC20;
    using FixedMath for uint256;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice Program state
    address public reward;
    uint256 public share;     // accumulated reward token per collected target
    uint256 public rewardBal; // last recorded balance of reward token
    uint256 public totalTarget;
    mapping(address => uint256) public tBalance;
    mapping(address => uint256) public rewarded; // reward token per collected target per user

    event Distributed(address indexed usr, address indexed token, uint256 amount);

    constructor() Trust(address(0)) { }

    function initialize(address _divider, FeedParams memory _feedParams, address _reward) public {
        super.initialize(_divider, _feedParams);

        setIsTrusted(_divider, true);
        reward = _reward;
        ERC20(stake).approve(_divider, type(uint256).max);
    }

    function notify(address _usr, uint256 amt, bool join) public override requiresTrust {
        _distribute(_usr);
        if (amt > 0) {
            if (join) {
                totalTarget    += amt;
                tBalance[_usr] += amt;
            } else {
                // else `exit`
                totalTarget    -= amt;
                tBalance[_usr] -= amt;
            }
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

    modifier onlyPeriphery() {
        require(Divider(divider).periphery() == msg.sender, Errors.OnlyPeriphery);
        _;
    }

}
