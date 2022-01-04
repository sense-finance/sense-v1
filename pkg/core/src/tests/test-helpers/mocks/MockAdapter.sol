// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { CropAdapter } from "../../../adapters/CropAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockTarget.sol";

contract MockAdapter is CropAdapter {
    using FixedMath for uint256;

    uint256 internal value;
    uint256 public INITIAL_VALUE;
    address public under;
    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 public onZeroRedeemCalls;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint48 _minm,
        uint48 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level,
        address _reward
    ) CropAdapter(_divider, _target, _oracle, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _tilt, _level, _reward) {}

    function _scale() internal virtual override returns (uint256 _value) {
        if (value > 0) return value;
        if (INITIAL_VALUE == 0) {
            INITIAL_VALUE = 1e18;
        }
        uint256 gps = GROWTH_PER_SECOND.fmul(99 * (10**(18 - 2)), FixedMath.WAD);
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        _value = lscale.value > 0 ? (gps * timeDiff).fmul(lscale.value, FixedMath.WAD) + lscale.value : INITIAL_VALUE;
    }

    function _claimReward() internal virtual override {
        //        MockToken(reward).mint(address(this), 1e18);
    }

    function wrapUnderlying(uint256 uBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        MockToken underlying = MockToken(target.underlying());
        underlying.transferFrom(msg.sender, address(this), uBal);
        uint256 mintAmount = uBal.fdivUp(lscale.value, FixedMath.WAD);
        target.mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        target.transferFrom(msg.sender, address(this), tBal); // pull target
        uint256 mintAmount = tBal.fmul(lscale.value, FixedMath.WAD);
        MockToken(target.underlying()).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        return 1e18;
    }

    function underlying() external view override returns (address) {
        return MockTarget(target).underlying();
    }

    function onZeroRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onZeroRedeemCalls++;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }
}
