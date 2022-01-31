// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { BaseAdapter } from "../../../adapters/BaseAdapter.sol";
import { CropAdapter } from "../../../adapters/CropAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Divider } from "../../../Divider.sol";
import { Claim } from "../../../tokens/Claim.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockToken.sol";

contract MockAdapter is CropAdapter {
    using FixedMath for uint256;

    uint256 internal value;
    uint256 public INITIAL_VALUE;
    address public under;
    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 public onZeroRedeemCalls;

    struct LScale {
        // Timestamp of the last scale value
        uint256 timestamp;
        // Last scale value
        uint256 value;
    }

    /// @notice Cached scale value from the last call to `scale()`
    LScale public lscale;

    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level,
        address _reward
    )
        CropAdapter(
            _divider,
            _target,
            MockTarget(_target).underlying(),
            _oracle,
            _ifee,
            _stake,
            _stakeSize,
            _minm,
            _maxm,
            _mode,
            _tilt,
            _level,
            _reward
        )
    {}

    function scale() external virtual override returns (uint256 _value) {
        if (value > 0) {
            _value = value;
            lscale.value = _value;
            lscale.timestamp = block.timestamp;
        }
        if (INITIAL_VALUE == 0) {
            INITIAL_VALUE = 1e18;
        }
        uint256 gps = GROWTH_PER_SECOND.fmul(99 * (10**(18 - 2)), FixedMath.WAD);
        uint256 timeDiff = block.timestamp - lscale.timestamp;
        _value = lscale.value > 0 ? (gps * timeDiff).fmul(lscale.value, FixedMath.WAD) + lscale.value : INITIAL_VALUE;

        if (_value != lscale.value) {
            // update value only if different than the previous
            lscale.value = _value;
            lscale.timestamp = block.timestamp;
        }
    }

    function scaleStored() external view virtual override returns (uint256 _value) {
        return lscale.value;
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

    function doInitSeries(uint256 maturity, address sponsor) external {
        Divider(divider).initSeries(address(this), maturity, sponsor);
    }

    function doIssue(uint256 maturity, uint256 tBal) external {
        MockTarget(target).transferFrom(msg.sender, address(this), tBal);
        Divider(divider).issue(address(this), maturity, tBal);
        (address zero, address claim, , , , , , , ) = Divider(divider).series(address(this), maturity);
        MockToken(zero).transfer(msg.sender, MockToken(zero).balanceOf(address(this)));
        MockToken(claim).transfer(msg.sender, MockToken(claim).balanceOf(address(this)));
    }

    function doCombine(uint256 maturity, uint256 uBal) external returns (uint256 tBal) {
        tBal = Divider(divider).combine(address(this), maturity, uBal);
    }

    function doRedeemZero(uint256 maturity, uint256 uBal) external {
        Divider(divider).redeemZero(address(this), maturity, uBal);
    }
}

contract MockBaseAdapter is BaseAdapter {
    constructor(
        address _divider,
        address _target,
        address _oracle,
        uint64 _ifee,
        address _stake,
        uint256 _stakeSize,
        uint256 _minm,
        uint256 _maxm,
        uint16 _mode,
        uint64 _tilt,
        uint16 _level
    )
        BaseAdapter(
            _divider,
            _target,
            MockTarget(_target).underlying(),
            _oracle,
            _ifee,
            _stake,
            _stakeSize,
            _minm,
            _maxm,
            _mode,
            _tilt,
            _level
        )
    {}

    function scale() external virtual override returns (uint256 _value) {
        return 100e18;
    }

    function scaleStored() external view virtual override returns (uint256) {
        return 100e18;
    }

    function wrapUnderlying(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function unwrapTarget(uint256 amount) external override returns (uint256) {
        return 0;
    }

    function getUnderlyingPrice() external view override returns (uint256) {
        return 1e18;
    }

    function doSetAdapter(Divider d, address _adapter) public {
        d.setAdapter(_adapter, true);
    }
}
