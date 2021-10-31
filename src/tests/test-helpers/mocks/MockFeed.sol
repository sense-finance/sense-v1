// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import { ERC20 } from "@rari-capital/solmate/src/erc20/ERC20.sol";
import { BaseFeed } from "../../../feeds/BaseFeed.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { MockTarget } from "./MockTarget.sol";

contract MockFeed is BaseFeed {
    using FixedMath for uint256;

    uint256 internal value;
    uint256 internal _tilt = 0;
    uint256 public INITIAL_VALUE;
    address public under;

    function _scale() internal override virtual returns (uint256 _value) {
        if (value > 0) return value;
        uint8 tDecimals = ERC20(feedParams.target).decimals();
        if (INITIAL_VALUE == 0)  {
            if (tDecimals != 18) {
                INITIAL_VALUE = tDecimals < 18 ? 0.1e18 / (10**(18 - tDecimals)) : 0.1e18 * (10**(tDecimals - 18));
            } else {
                INITIAL_VALUE = 0.1e18;
            }
        }
        uint256 gps = feedParams.delta.fmul(99 * (10 ** (tDecimals - 2)), 10**tDecimals); // delta - 1%;
        uint256 timeDiff = block.timestamp - _lscale.timestamp;
        _value = _lscale.value > 0 ? (gps * timeDiff).fmul(_lscale.value, 10**tDecimals) + _lscale.value : INITIAL_VALUE;
    }

    function underlying() external virtual override returns (address) {
        return MockTarget(target).underlying();
    }

    function tilt() external override virtual returns (uint256 _value) {
        return _tilt;
    }

    function setScale(uint256 _value) external {
        value = _value;
    }

    function setOracle(address _oracle) external {
        oracle = _oracle;
    }

    function setTilt(uint256 _value) external {
        _tilt = _value;
    }
}

// used in simulated env deployment scripts
contract SimpleAdminFeed {
    using FixedMath for uint256;

    address public owner;
    address public target;
    string public name;
    string public symbol;
    uint256 internal value = 1e18;
    uint256 public constant INITIAL_VALUE = 1e18;

    constructor(
        address _target,
        string memory _name,
        string memory _symbol,
    ) {
        target = _target;
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    function scale() external virtual returns (uint256 _value) {
        return value;
    }

    function tilt() external virtual returns (uint256 _value) {
        return 0;
    }

    function setScale(uint256 _value) external {
        require(msg.sender == owner, "Only owner");
        value = _value;
    }
}