// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import "./ERC4626.test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { AddressBook } from "@sense-finance/v1-utils/addresses/AddressBook.sol";
import { ForkTest } from "@sense-finance/v1-core/tests/test-helpers/ForkTest.sol";

/// @title ERC4626 Property Tests
/// @author Taken from https://github.com/a16z/erc4626-tests
/// @dev Modified to work with a deployed vault whose address is read from env.
/// It also provides the `_needsRolling` property and support for vaults where `deal()` can't find the storage slot.
contract ERC4626StdTest is ERC4626Test, ForkTest {
    address public userWithAssets;

    function setUp() public override {
        fork();
        try vm.envAddress("ERC4626_ADDRESS") returns (address vault) {
            _vault_ = vault;
        } catch {
            _vault_ = AddressBook.IMUSD;
        }
        console.log("Running tests for token: ", ERC4626(_vault_).symbol());

        try vm.envAddress("USER_WITH_ASSETS") {
            userWithAssets = vm.envAddress("USER_WITH_ASSETS");
        } catch {}
        _underlying_ = address(ERC4626(_vault_).asset());
        _delta_ = 10;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
        // some protocols will revert if doing a deposit followed by a withdrawal on the same block
        _needsRolling = true;
    }

    function setUpVault(Init memory init) public override {
        uint256 maxAssetPerUser;

        if (userWithAssets != address(0)) {
            // init vault
            vm.startPrank(userWithAssets);
            ERC20(_underlying_).approve(_vault_, type(uint256).max);
            IERC4626(_vault_).deposit(1 * 10**ERC20(_underlying_).decimals(), userWithAssets);
            vm.stopPrank();

            // user asset balance
            uint256 assetBal = ERC20(_underlying_).balanceOf(userWithAssets);
            maxAssetPerUser = assetBal / 2 / N;
        }

        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // shares
            if (userWithAssets == address(0)) {
                uint256 shares = init.share[i];
                deal(_underlying_, user, shares);
                _approve(_underlying_, user, _vault_, shares);
                vm.prank(user);
                try IERC4626(_vault_).deposit(shares, user) {} catch {
                    vm.assume(false);
                }
            } else {
                init.share[i] = bound(init.share[i], 0, maxAssetPerUser);
                uint256 shares = init.share[i];
                vm.prank(userWithAssets);
                ERC4626(_vault_).deposit(shares, user);
            }

            // assets
            if (userWithAssets == address(0)) {
                uint256 assets = init.asset[i];
                deal(_underlying_, user, assets);
            } else {
                init.asset[i] = bound(init.asset[i], 0, maxAssetPerUser);
                uint256 assets = init.asset[i];
                vm.prank(userWithAssets);
                ERC20(_underlying_).transfer(user, assets);
            }

            if (_needsRolling) vm.roll(block.number + 1);
        }
    }
}
