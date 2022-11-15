// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { IEulerMarkets } from "@yield-daddy/src/euler/external/IEulerMarkets.sol";
import { IEulerEToken } from "@yield-daddy/src/euler/external/IEulerEToken.sol";
import { EulerERC4626Factory } from "@yield-daddy/src/euler/EulerERC4626Factory.sol";
import { ERC4626Factory } from "@yield-daddy/src/base/ERC4626Factory.sol";

import { EulerERC4626 } from "./EulerERC4626.sol";
import { ERC4626WrapperFactory } from "../base/ERC4626WrapperFactory.sol";

/// @title EulerERC4626WrapperFactory
/// @author Yield Daddy (Timeless Finance)
/// @notice This is NOT an adapter factory, it is a wrapper factory which allows one to
/// create ERC4626 wrappers for eTokens (Euler tokens)
contract EulerERC4626WrapperFactory is EulerERC4626Factory, ERC4626WrapperFactory {
    constructor(
        address _euler,
        IEulerMarkets _markets,
        address _restrictedAdmin,
        address _rewardsRecipient
    ) EulerERC4626Factory(_euler, _markets) ERC4626WrapperFactory(_restrictedAdmin, _rewardsRecipient) {}

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function createERC4626(ERC20 asset)
        external
        virtual
        override(EulerERC4626Factory, ERC4626Factory)
        returns (ERC4626 vault)
    {
        address eTokenAddress = markets.underlyingToEToken(address(asset));
        if (eTokenAddress == address(0)) {
            revert EulerERC4626Factory__ETokenNonexistent();
        }

        vault = new EulerERC4626{ salt: bytes32(0) }(asset, euler, IEulerEToken(eTokenAddress), rewardsRecipient);
        EulerERC4626(address(vault)).setIsTrusted(restrictedAdmin, true);

        emit CreateERC4626(asset, vault);
    }

    function computeERC4626Address(ERC20 asset)
        external
        view
        virtual
        override(EulerERC4626Factory, ERC4626Factory)
        returns (ERC4626 vault)
    {
        vault = ERC4626(
            _computeCreate2Address(
                keccak256(
                    abi.encodePacked(
                        // Deployment bytecode:
                        type(EulerERC4626).creationCode,
                        // Constructor arguments:
                        abi.encode(
                            asset,
                            euler,
                            IEulerEToken(markets.underlyingToEToken(address(asset))),
                            rewardsRecipient
                        )
                    )
                )
            )
        );
    }
}
