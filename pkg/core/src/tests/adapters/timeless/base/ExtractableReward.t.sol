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
import { Errors } from "@sense-finance/v1-utils/libs/Errors.sol";

contract ExtractableRewards is DSTestPlus {
    EulerMock public euler;
    EulerERC4626 public vault;
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

        vault = EulerERC4626(address(factory.createERC4626(underlying)));
        assertEq(vault.rewardsRecipient(), Constants.REWARDS_RECIPIENT, "rewards recipient incorrect");
    }

    function testSetRewardsRecipient() public {
        assertEq(vault.rewardsRecipient(), Constants.REWARDS_RECIPIENT);

        hevm.expectRevert("UNTRUSTED");
        hevm.prank(address(0x123));
        vault.setRewardsRecipient(address(0x111));

        // Can be changed by admin

        hevm.expectEmit(true, true, true, true);
        emit RewardsRecipientChanged(Constants.REWARDS_RECIPIENT, address(0x111));

        hevm.prank(Constants.RESTRICTED_ADMIN);
        vault.setRewardsRecipient(address(0x111));
        assertEq(vault.rewardsRecipient(), address(0x111));

        // Can be changed by the factory that deployed it

        hevm.expectEmit(true, true, true, true);
        emit RewardsRecipientChanged(address(0x111), address(0x222));

        hevm.prank(address(factory));
        vault.setRewardsRecipient(address(0x222));
        assertEq(vault.rewardsRecipient(), address(0x222));
    }

    function testExtractToken() public {
        // can extract someReward
        MockToken someReward = new MockToken("Some Reward", "SR", 18);
        someReward.mint(address(vault), 1e18);
        assertEq(someReward.balanceOf(address(vault)), 1e18);

        hevm.expectEmit(true, true, true, true);
        emit RewardsClaimed(address(someReward), Constants.REWARDS_RECIPIENT, 1e18);

        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 0);
        // anyone can call extract token
        hevm.prank(address(0xfede));
        vault.extractToken(address(someReward));
        assertEq(someReward.balanceOf(Constants.REWARDS_RECIPIENT), 1e18);

        // can NOT extract eToken
        address eToken = address(vault.eToken());
        hevm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        vault.extractToken(eToken);
    }

    event RewardsRecipientChanged(address indexed oldRecipient, address indexed newRecipient);
    event RewardsClaimed(address indexed token, address indexed recipient, uint256 indexed amount);
}
