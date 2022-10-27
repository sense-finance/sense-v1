// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { EulerMock } from "@yield-daddy/src/test/euler/mocks/EulerMock.sol";
import { MockToken } from "../../../test-helpers/mocks/MockToken.sol";
import { EulerERC4626 } from "../../../../adapters/abstract/erc4626/yield-daddy/euler/EulerERC4626.sol";
import { EulerETokenMock } from "@yield-daddy/src/test/euler/mocks/EulerETokenMock.sol";
import { EulerMarketsMock } from "@yield-daddy/src/test/euler/mocks/EulerMarketsMock.sol";

import { EulerERC4626WrapperFactory } from "../../../../adapters/abstract/erc4626/yield-daddy/euler/EulerERC4626WrapperFactory.sol";
import { Constants } from "../../../test-helpers/Constants.sol";

contract EulerERC4626WrapperFactoryTest is DSTestPlus {
    EulerMock public euler;
    MockToken public underlying;
    EulerETokenMock public eToken;
    EulerMarketsMock public markets;
    EulerERC4626WrapperFactory public factory;

    function setUp() public {
        euler = new EulerMock();
        underlying = new MockToken("USD Coin", "USDC", 6);
        eToken = new EulerETokenMock(underlying, euler);
        markets = new EulerMarketsMock();
        factory = new EulerERC4626WrapperFactory(
            address(euler),
            markets,
            Constants.RESTRICTED_ADMIN,
            Constants.REWARDS_RECIPIENT
        );

        markets.setETokenForUnderlying(address(underlying), address(eToken));
    }

    function testCreateERC4626() public {
        EulerERC4626 vault = EulerERC4626(address(factory.createERC4626(underlying)));

        assertEq(address(vault.rewardsRecipient()), address(Constants.REWARDS_RECIPIENT), "rewardsRecipient incorrect");
        assertEq(address(vault.eToken()), address(eToken), "eToken incorrect");
        assertEq(address(vault.euler()), address(euler), "euler incorrect");
    }

    function testComputeERC4626Address() public {
        EulerERC4626 vault = EulerERC4626(address(factory.createERC4626(underlying)));

        assertEq(
            address(factory.computeERC4626Address(underlying)),
            address(vault),
            "computed vault address incorrect"
        );
    }

    function testCantCreateERC4626ForAssetWithoutEToken() public {
        MockToken fakeAsset = new MockToken("Fake Coin", "FC", 18);
        hevm.expectRevert(abi.encodeWithSignature("EulerERC4626Factory__ETokenNonexistent()"));
        factory.createERC4626(fakeAsset);
    }
}
