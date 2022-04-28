// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { BaseAdapter } from "../../../adapters/BaseAdapter.sol";
import { CropsAdapter } from "../../../adapters/CropsAdapter.sol";
import { CropAdapter } from "../../../adapters/CropAdapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Divider } from "../../../Divider.sol";
import { YT } from "../../../tokens/YT.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockToken.sol";

contract MockAdapter is CropAdapter {
    using FixedMath for uint256;

    uint256 internal scaleOverride;
    uint256 public INITIAL_VALUE = 1e18;
    address public under;
    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 public onRedeemCalls;
    uint256 public scalingFactor;

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
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) CropAdapter(_divider, _target, _underlying, _ifee, _adapterParams, _reward) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function scale() external virtual override returns (uint256 _scale) {
        if (scaleOverride > 0) {
            _scale = scaleOverride;
            lscale.value = scaleOverride;
            lscale.timestamp = block.timestamp;
        } else {
            uint256 gps = GROWTH_PER_SECOND.fmul(99 * (10**(18 - 2)));
            uint256 timeDiff = block.timestamp - lscale.timestamp;
            _scale = lscale.value > 0 ? (gps * timeDiff).fmul(lscale.value) + lscale.value : INITIAL_VALUE;

            if (_scale != lscale.value) {
                // update value only if different than the previous
                lscale.value = _scale;
                lscale.timestamp = block.timestamp;
            }
        }
    }

    function scaleStored() external view virtual override returns (uint256) {
        return lscale.value == 0 ? INITIAL_VALUE : lscale.value;
    }

    function _claimReward() internal virtual override {
        // MockToken(reward).mint(address(this), 1e18);
    }

    function wrapUnderlying(uint256 uBal) public virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        MockToken underlying = MockToken(target.underlying());
        underlying.transferFrom(msg.sender, address(this), uBal);
        uint256 mintAmount = uBal.fdivUp(lscale.value);
        mintAmount = underlying.decimals() > target.decimals()
            ? mintAmount / scalingFactor
            : mintAmount * scalingFactor;
        target.mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        MockToken underlying = MockToken(target.underlying());
        target.transferFrom(msg.sender, address(this), tBal); // pull target
        uint256 mintAmount = tBal.fmul(lscale.value);
        mintAmount = underlying.decimals() > target.decimals()
            ? mintAmount * scalingFactor
            : mintAmount / scalingFactor;
        MockToken(target.underlying()).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        return 1e18;
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
    }

    function setScale(uint256 _scaleOverride) external {
        scaleOverride = _scaleOverride;
    }

    function doInitSeries(uint256 maturity, address sponsor) external {
        Divider(divider).initSeries(address(this), maturity, sponsor);
    }

    function doIssue(uint256 maturity, uint256 tBal) external {
        MockTarget(target).transferFrom(msg.sender, address(this), tBal);
        Divider(divider).issue(address(this), maturity, tBal);
        (address pt, , address yt, , , , , , ) = Divider(divider).series(address(this), maturity);
        MockToken(pt).transfer(msg.sender, MockToken(pt).balanceOf(address(this)));
        MockToken(yt).transfer(msg.sender, MockToken(yt).balanceOf(address(this)));
    }

    function doCombine(uint256 maturity, uint256 uBal) external returns (uint256 tBal) {
        tBal = Divider(divider).combine(address(this), maturity, uBal);
    }

    function doRedeemPrincipal(uint256 maturity, uint256 uBal) external {
        Divider(divider).redeem(address(this), maturity, uBal);
    }
}

contract MockCropsAdapter is CropsAdapter {
    using FixedMath for uint256;

    uint256 internal scaleOverride;
    uint256 public INITIAL_VALUE;
    address public under;
    uint256 internal GROWTH_PER_SECOND = 792744799594; // 25% APY
    uint256 public onRedeemCalls;
    uint256 public scalingFactor;

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
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) CropsAdapter(_divider, _target, _underlying, _ifee, _adapterParams, _rewardTokens) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function scale() external virtual override returns (uint256 _scale) {
        if (scaleOverride > 0) {
            _scale = scaleOverride;
            lscale.value = scaleOverride;
            lscale.timestamp = block.timestamp;
        } else {
            uint256 gps = GROWTH_PER_SECOND.fmul(99 * (10**(18 - 2)));
            uint256 timeDiff = block.timestamp - lscale.timestamp;
            _scale = lscale.value > 0 ? (gps * timeDiff).fmul(lscale.value) + lscale.value : INITIAL_VALUE;

            if (_scale != lscale.value) {
                // update value only if different than the previous
                lscale.value = _scale;
                lscale.timestamp = block.timestamp;
            }
        }
    }

    function scaleStored() external view virtual override returns (uint256 _value) {
        return lscale.value;
    }

    function _claimRewards() internal virtual override {
        // for (uint i = 0; i < rewardTokens.length; i++) {
        //     MockToken(rewardTokens[i]).mint(address(this), 1e18);
        // }
    }

    function wrapUnderlying(uint256 uBal) public virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        MockToken underlying = MockToken(target.underlying());
        underlying.transferFrom(msg.sender, address(this), uBal);
        uint256 mintAmount = uBal.fdivUp(lscale.value);
        mintAmount = underlying.decimals() > target.decimals()
            ? mintAmount / scalingFactor
            : mintAmount * scalingFactor;
        target.mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function unwrapTarget(uint256 tBal) external virtual override returns (uint256) {
        MockTarget target = MockTarget(target);
        MockToken underlying = MockToken(target.underlying());
        target.transferFrom(msg.sender, address(this), tBal); // pull target
        uint256 mintAmount = tBal.fmul(lscale.value);
        mintAmount = underlying.decimals() > target.decimals()
            ? mintAmount * scalingFactor
            : mintAmount / scalingFactor;
        MockToken(target.underlying()).mint(msg.sender, mintAmount);
        return mintAmount;
    }

    function getUnderlyingPrice() external view virtual override returns (uint256) {
        return 1e18;
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
    }

    function setScale(uint256 _scaleOverride) external {
        scaleOverride = _scaleOverride;
    }

    function doInitSeries(uint256 maturity, address sponsor) external {
        Divider(divider).initSeries(address(this), maturity, sponsor);
    }

    function doIssue(uint256 maturity, uint256 tBal) external {
        MockTarget(target).transferFrom(msg.sender, address(this), tBal);
        Divider(divider).issue(address(this), maturity, tBal);
        (address pt, , address yt, , , , , , ) = Divider(divider).series(address(this), maturity);
        MockToken(pt).transfer(msg.sender, MockToken(pt).balanceOf(address(this)));
        MockToken(yt).transfer(msg.sender, MockToken(yt).balanceOf(address(this)));
    }

    function doCombine(uint256 maturity, uint256 uBal) external returns (uint256 tBal) {
        tBal = Divider(divider).combine(address(this), maturity, uBal);
    }

    function doRedeemPrincipal(uint256 maturity, uint256 uBal) external {
        Divider(divider).redeem(address(this), maturity, uBal);
    }
}

contract MockBaseAdapter is BaseAdapter {
    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {}

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
