// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { IEulerEToken } from "@yield-daddy/src/euler/external/IEulerEToken.sol";
import { EulerERC4626 as Base } from "@yield-daddy/src/euler/EulerERC4626.sol";
import { ExtractableReward } from "../../../extensions/ExtractableReward.sol";

/// @title EulerERC4626
/// @author forked from Yield Daddy (Timeless Finance)
/// @notice ERC4626 wrapper for Euler Finance
contract EulerERC4626 is Base, ExtractableReward {
    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------
    constructor(
        ERC20 _asset,
        address _euler,
        IEulerEToken _eToken,
        address _rewardsRecipient
    ) Base(_asset, _euler, _eToken) ExtractableReward(_rewardsRecipient) {}

    /// -----------------------------------------------------------------------
    /// Overrides
    /// -----------------------------------------------------------------------
    function _isValid(address _token) internal override returns (bool) {
        return _token != address(eToken);
    }
}
