// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "solmate/erc20/ERC20.sol";
import { BaseFeed } from "../../../feeds/BaseFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";

contract MockFeed is BaseFeed {
    using FixedMath for uint256;

    uint256 internal value;
    uint256 internal _tilt = 0;
    uint256 public INITIAL_VALUE;

    function _scale() internal override virtual returns (uint256 _value) {
        if (value > 0) return value;
        uint8 tDecimals = ERC20(target).decimals();
        if (INITIAL_VALUE == 0)  {
            if (tDecimals != 18) {
                INITIAL_VALUE = tDecimals < 18 ? 0.1e18 / (10**(18 - tDecimals)) : 0.1e18 * (10**(tDecimals - 18));
            } else {
                INITIAL_VALUE = 0.1e18;
            }
        }
        uint256 gps = delta.fmul(99 * (10 ** (tDecimals - 2)), 10**tDecimals); // delta - 1%;
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        _value = lscale.value > 0 ? (gps * timeDiff).fmul(lscale.value, 10**tDecimals) + lscale.value : INITIAL_VALUE;
    }

    function tilt() external override virtual returns (uint256 _value) {
        return _tilt;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }

    function setTilt(uint256 _value) external {
        _tilt = _value;
    }

}
