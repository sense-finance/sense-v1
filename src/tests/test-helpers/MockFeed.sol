// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { BaseFeed } from "../../feed/BaseFeed.sol";
import { WadMath } from "../../external/WadMath.sol";

contract MockFeed is BaseFeed {
    using WadMath for uint256;

    uint256 internal value;
    uint256 public constant INITIAL_VALUE = 0.1e18;

    function _scale() internal override virtual returns (uint256 _value) {
        uint256 gps = delta.wmul(99e16); // delta - 1%;
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        if (value > 0) return value;
        _value = lscale.value > 0 ? (gps * timeDiff).wmul(lscale.value) + lscale.value :  0.1e18;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }

}
