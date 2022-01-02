// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { CropAdapter } from "../../../adapters/CropAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockTarget.sol";

contract MockAdapter is CropAdapter {
    using FixedMath for uint256;

    uint256 internal value;
    uint128 internal _tilt = 0;
    uint8 internal _level;
    uint256 public INITIAL_VALUE;
    address public under;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint256 _delta,
        uint256 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint8 _mode,
        address _reward
    ) CropAdapter(_divider, _target, _oracle, _delta, _ifee, _stake, _stakeSize, _minm, _maxm, _mode, _reward) {}

    function _scale() internal virtual override returns (uint256 _value) {
        if (value > 0) return value;
        if (INITIAL_VALUE == 0) {
            INITIAL_VALUE = 1e18;
        }
        uint256 gps = delta.fmul(99 * (10**(18 - 2)), FixedMath.WAD); // delta - 1%;
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

    function tilt() external view virtual override returns (uint128) {
        return _tilt;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }

    function setTilt(uint128 _value) external {
        _tilt = _value;
    }

    function setLevel(uint256 _level) external {
        level = _level;
    }
}
