// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { BaseAdapter } from "../../../adapters/abstract/BaseAdapter.sol";
import { Crops } from "../../../adapters/abstract/extensions/Crops.sol";
import { Crop } from "../../../adapters/abstract/extensions/Crop.sol";
import { ERC4626Adapter } from "../../../adapters/abstract/erc4626/ERC4626Adapter.sol";
import { FixedMath } from "../../../external/FixedMath.sol";
import { Divider } from "../../../Divider.sol";
import { YT } from "../../../tokens/YT.sol";
import { MockTarget } from "./MockTarget.sol";
import { MockToken } from "./MockToken.sol";
import { ERC4626 } from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import { Errors } from "@sense-finance/v1-utils/src/libs/Errors.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// Mock adapter
contract MockAdapter is BaseAdapter {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

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
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _rewardsRecipient, _ifee, _adapterParams) {
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

    function extractToken(address token) external override {
        // Check that token is neither the target nor the stake
        if (token == target || token == adapterParams.stake) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
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

// Mock crop adapter
contract MockCropAdapter is BaseAdapter, Crop {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

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
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) Crop(_divider, _reward) BaseAdapter(_divider, _target, _underlying, _rewardsRecipient, _ifee, _adapterParams) {
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
        super._claimReward();
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

    function extractToken(address token) external override {
        // Check that token is neither the target, the stake nor the reward
        if (token == target || token == adapterParams.stake || token == reward) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
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

// Mock crops adapter
contract MockCropsAdapter is BaseAdapter, Crops {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

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
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    )
        Crops(_divider, _rewardTokens)
        BaseAdapter(_divider, _target, _underlying, _rewardsRecipient, _ifee, _adapterParams)
    {
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
        super._claimRewards();
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

    function extractToken(address token) external override {
        for (uint256 i = 0; i < rewardTokens.length; ) {
            if (token == rewardTokens[i]) revert Errors.TokenNotSupported();
            unchecked {
                ++i;
            }
        }

        // Check that token is neither the target nor the stake
        if (token == target || token == adapterParams.stake) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
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
contract Mock4626Adapter is ERC4626Adapter {
    using FixedMath for uint256;

    uint256 public onRedeemCalls;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) {}

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
contract Mock4626CropAdapter is ERC4626Adapter, Crop {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    uint256 public onRedeemCalls;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address _reward
    ) ERC4626Adapter(_divider, _target, rewardsRecipient, _ifee, _adapterParams) Crop(_divider, _reward) {}

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

    function extractToken(address token) external override {
        // Check that token is neither the target, the stake nor the reward
        if (token == target || token == adapterParams.stake || token == reward) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
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

// Mock ERC4626 crops adapter
contract Mock4626CropsAdapter is ERC4626Adapter, Crops {
    using FixedMath for uint256;
    using SafeTransferLib for ERC20;

    uint256 public onRedeemCalls;
    uint256 public scalingFactor;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams,
        address[] memory _rewardTokens
    ) ERC4626Adapter(_divider, _target, _rewardsRecipient, _ifee, _adapterParams) Crops(_divider, _rewardTokens) {
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

    function extractToken(address token) external override {
        for (uint256 i = 0; i < rewardTokens.length; ) {
            if (token == rewardTokens[i]) revert Errors.TokenNotSupported();
            unchecked {
                ++i;
            }
        }

        // Check that token is neither the target nor the stake
        if (token == target || token == adapterParams.stake) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
    }

    function onRedeem(
        uint256, /* uBal */
        uint256, /* mscale */
        uint256, /* maxscale */
        uint256 /* tBal */
    ) public virtual override {
        onRedeemCalls++;
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

// Mock base adapter
contract MockBaseAdapter is BaseAdapter {
    using SafeTransferLib for ERC20;

    constructor(
        address _divider,
        address _target,
        address _underlying,
        address _rewardsRecipient,
        uint128 _ifee,
        AdapterParams memory _adapterParams
    ) BaseAdapter(_divider, _target, _underlying, _rewardsRecipient, _ifee, _adapterParams) {}

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

    function extractToken(address token) external override {
        // Check that token is neither the target nor the stake
        if (token == target || token == adapterParams.stake) revert Errors.TokenNotSupported();
        ERC20 t = ERC20(token);
        uint256 tBal = t.balanceOf(address(this));
        t.safeTransfer(rewardsRecipient, tBal);
        emit RewardsClaimed(token, rewardsRecipient, tBal);
    }
}
