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
    uint256 public INITIAL_VALUE;
    address public under;

    function _scale() internal virtual override returns (uint256 _value) {
        if (value > 0) return value;
        if (INITIAL_VALUE == 0) {
            INITIAL_VALUE = 1e18;
        }
        uint256 gps = adapterParams.delta.fmul(99 * (10**(18 - 2)), FixedMath.WAD); // delta - 1%;
        uint256 timeDiff = block.timestamp - _lscale.timestamp;
        _value = _lscale.value > 0
            ? (gps * timeDiff).fmul(_lscale.value, FixedMath.WAD) + _lscale.value
            : INITIAL_VALUE;
    }

    function _claimReward() internal virtual override {
        //        MockToken(reward).mint(address(this), 1e18);
    }

    function wrapUnderlying(uint256 uBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(adapterParams.target);
        MockToken underlying = MockToken(target.underlying());
        underlying.transferFrom(msg.sender, address(this), uBal);
        uint256 mintAmount = uBal.fdivUp(_lscale.value, FixedMath.WAD);
        target.mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(adapterParams.target);
        target.transferFrom(msg.sender, address(this), tBal); // pull target
        uint256 mintAmount = tBal.fmul(_lscale.value, FixedMath.WAD);
        MockToken(target.underlying()).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        return 1e18;
    }

    function underlying() external view override returns (address) {
        return MockTarget(adapterParams.target).underlying();
    }

    function tilt() external virtual override returns (uint128) {
        return _tilt;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }

    function setOracle(address _oracle) external {
        adapterParams.oracle = _oracle;
    }

    function setTilt(uint128 _value) external {
        _tilt = _value;
    }

    function setMode(uint8 _mode) external {
        adapterParams.mode = _mode;
    }
}
