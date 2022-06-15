// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { BaseAdapter } from "../../../adapters/abstract/BaseAdapter.sol";
import { Crops } from "../../../adapters/abstract/extensions/Crops.sol";
import { Crop } from "../../../adapters/abstract/extensions/Crop.sol";
import { ERC4626Adapter } from "../../../adapters/abstract/ERC4626Adapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Divider } from "../../../Divider.sol";
import { YT } from "../../../tokens/YT.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockToken.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";

// Mock crop adapter
contract MockAdapter is BaseAdapter, Crop {
    using FixedMath for uint256;

    uint256 internal scaleOverride;
    uint256 public INITIAL_VALUE = 1e18;
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
    ) Crop(_divider, _reward) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
        super.notify(_usr, amt, join);
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
}

// Mock ERC4626 crop adapter
contract Mock4626Adapter is ERC4626Adapter, Crop {
    using FixedMath for uint256;

    uint256 public onRedeemCalls;
    uint256 public scalingFactor;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626Adapter(_divider, _target, _ifee, _adapterParams) Crop(_divider, _reward) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crop) {
        super.notify(_usr, amt, join);
    }

    function lscale() external returns (uint256, uint256) {
        return (0, ERC4626(target).convertToAssets(BASE_UINT));
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
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

// Mock crops adapter
contract MockCropsAdapter is BaseAdapter, Crops {
    using FixedMath for uint256;

    uint256 internal scaleOverride;
    uint256 public INITIAL_VALUE = 1e18;
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
    ) Crops(_divider, _rewardTokens) BaseAdapter(_divider, _target, _underlying, _ifee, _adapterParams) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
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

    // function doRedeemPrincipal(uint256 maturity, uint256 uBal) external {
    //     Divider(divider).redeem(address(this), maturity, uBal);
    // }
}

// Mock ERC4626 crops adapter
contract Mock4626CropsAdapter is ERC4626Adapter, Crops {
    using FixedMath for uint256;

    uint256 public onRedeemCalls;
    uint256 public scalingFactor;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) ERC4626Adapter(_divider, _target, _ifee, _adapterParams) Crops(_divider, _rewardTokens) {
        uint256 tDecimals = MockTarget(_target).decimals();
        uint256 uDecimals = MockTarget(_underlying).decimals();
        scalingFactor = 10**(tDecimals > uDecimals ? tDecimals - uDecimals : uDecimals - tDecimals);
    }

    function notify(
        address _usr,
        uint256 amt,
        bool join
    ) public override(BaseAdapter, Crops) {
        super.notify(_usr, amt, join);
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
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

// Mock base adapter
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
}
